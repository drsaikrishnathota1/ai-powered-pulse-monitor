import AVFoundation
import Charts
import SwiftUI

struct MeasureView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var healthKit: HealthKitManager
    @StateObject private var engine = HeartRateEngine()

    @State private var isMeasuring = false
    @State private var startDate: Date?
    @State private var progress: Double = 0
    @State private var secondsLeft: Int = Int(MeasurementConstants.captureDurationSeconds)
    @State private var showDenied = false
    @State private var sessionMessage: SessionMessage?
    @State private var latestReading: HeartReading?

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let successHaptic = UINotificationFeedbackGenerator()

    private var captureDuration: TimeInterval { MeasurementConstants.captureDurationSeconds }
    private var displayedBPM: Int? { isMeasuring ? engine.bpm : latestReading?.bpm }
    private var displayedQuality: Double { isMeasuring ? engine.quality : (latestReading?.quality ?? 0) }
    private var hasCompletedReading: Bool { !isMeasuring && latestReading != nil }
    private var timerLabel: String {
        if isMeasuring {
            return "\(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))"
        }
        return hasCompletedReading ? "Done" : "1:00"
    }
    private var recentAverageBPM: Int? {
        let recentReadings = Array(history.readings.prefix(7))
        guard !recentReadings.isEmpty else { return nil }
        let total = recentReadings.reduce(0) { $0 + $1.bpm }
        return Int(round(Double(total) / Double(recentReadings.count)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PulseTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        header

                        #if targetEnvironment(simulator)
                        if !AppLaunchConfiguration.isAppStoreScreenshotMode {
                        simulatorBanner
                        }
                        #endif

                        measurementCard

                        if let sessionMessage {
                            sessionMessageCard(sessionMessage)
                        }

                        if let err = engine.cameraError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        if engine.torchWarmWarning, engine.isRunning {
                            Label(
                                "One-minute session: if the LED feels hot, lift your finger for a few seconds, then continue.",
                                systemImage: "flame.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.9))
                            .padding(.horizontal)
                        }

                        tipsCard
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle("Camvital Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { date in
                guard isMeasuring, let start = startDate else { return }
                let elapsed = date.timeIntervalSince(start)
                progress = min(1, elapsed / captureDuration)
                let left = max(0, captureDuration - elapsed)
                secondsLeft = Int(ceil(left))
                if elapsed >= captureDuration {
                    completeMeasurement()
                }
            }
            .alert("Camera access needed", isPresented: $showDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable camera in Settings to measure pulse with the flash.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PulseTheme.actionGradient)
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black.opacity(0.78))
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Guided pulse scan")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("A calm 60-second camera session with live signal quality, progress, and clear wellness guidance.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            HStack(spacing: 8) {
                scanPill("60 sec", icon: "timer")
                scanPill("On device", icon: "lock.shield")
                scanPill("Wellness", icon: "heart.text.square")
            }

            Text("For wellness tracking only. Not a medical device or emergency monitor.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(PulseTheme.cardStrong))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PulseTheme.stroke))
    }

    private func scanPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    #if targetEnvironment(simulator)
    private var simulatorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(PulseTheme.accent)
            Text("Simulator has no camera. Build on a physical device to measure a live pulse.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PulseTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseTheme.stroke))
    }
    #endif

    private var measurementCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                statusBadge
                Spacer()
                Text(timerLabel)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(isMeasuring ? PulseTheme.accent : .white.opacity(0.72))
            }

            ZStack {
                Circle()
                    .stroke(PulseTheme.stroke, lineWidth: 14)
                    .frame(width: 210, height: 210)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [PulseTheme.accent, PulseTheme.accent2, PulseTheme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 210, height: 210)
                    .animation(.easeInOut(duration: 0.15), value: progress)

                VStack(spacing: 10) {
                    Text(displayedBPM.map { "\($0)" } ?? "—")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(isMeasuring ? "LIVE BPM" : (hasCompletedReading ? "LATEST BPM" : "BPM"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))

                    qualityBar

                    if let bpm = displayedBPM {
                        let zone = PulseHeartZone.zone(for: bpm, age: settings.age)
                        Text(zone.title)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().stroke(PulseTheme.stroke))
                    }
                }
            }

            if isMeasuring {
                readinessStrip
                waveform
            } else if let latestReading {
                resultSummaryCard(for: latestReading)
            } else {
                readinessStrip
            }

            Button(action: toggleMeasure) {
                Label(isMeasuring ? "Stop session" : (hasCompletedReading ? "Scan again" : "Start 1-minute scan"), systemImage: isMeasuring ? "stop.fill" : "waveform.path.ecg")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isMeasuring ? PulseTheme.dangerGradient : PulseTheme.actionGradient)
                    )
                    .foregroundStyle(.black.opacity(isMeasuring ? 0.95 : 0.9))
            }
            .buttonStyle(.plain)
            #if targetEnvironment(simulator)
            .disabled(true)
            .opacity(0.55)
            #endif
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PulseTheme.card)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PulseTheme.stroke)
        )
    }

    private var statusBadge: some View {
        Label(
            isMeasuring ? "Scanning" : (hasCompletedReading ? "Result ready" : "Ready"),
            systemImage: isMeasuring ? "dot.radiowaves.left.and.right" : (hasCompletedReading ? "checkmark.circle.fill" : "checkmark.seal.fill")
        )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isMeasuring ? PulseTheme.accent : PulseTheme.success)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var readinessStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scan readiness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text("Final BPM uses the full minute")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.42))
            }

            HStack(spacing: 8) {
                readinessItem("Cover lens", icon: "camera.metering.center.weighted")
                readinessItem("Stay still", icon: "hand.raised.fill")
                readinessItem("Gentle grip", icon: "sparkles")
            }
        }
    }

    private func readinessItem(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.055)))
    }

    private func sessionMessageCard(_ message: SessionMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(message.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message.detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PulseTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseTheme.stroke))
    }

    private func resultSummaryCard(for reading: HeartReading) -> some View {
        let insight = PulseReadingInsight.reading(for: reading.bpm)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest result")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(reading.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer()

                Label("Saved to history", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.badge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(insight.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(insight.tint.opacity(0.14)))

                    Text(insight.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(insight.detail)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(reading.bpm)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("BPM")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 10) {
                resultMetricChip(title: "Signal", value: "\(Int(reading.quality * 100))%", systemImage: "waveform.path")
                if let recentAverageBPM {
                    resultMetricChip(title: "Recent avg", value: "\(recentAverageBPM) BPM", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            Text(insight.suggestion)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))

            bloodPressureReferenceSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PulseTheme.stroke))
    }

    private func resultMetricChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.055)))
    }

    private var bloodPressureReferenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blood pressure example")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.56))

            HStack(alignment: .top, spacing: 10) {
                pressureReferenceMetric(
                    title: "Systolic",
                    value: "120",
                    unit: "mmHg",
                    detail: "Top number: pressure in the arteries while the heart beats."
                )
                pressureReferenceMetric(
                    title: "Diastolic",
                    value: "80",
                    unit: "mmHg",
                    detail: "Bottom number: pressure in the arteries while the heart rests between beats."
                )
            }

            Text("Reference only: this camera scan measures pulse, not blood pressure. Use a validated upper-arm cuff monitor for BP numbers.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func pressureReferenceMetric(title: String, value: String, unit: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.055)))
    }

    private var qualityBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Signal")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("\(Int(displayedQuality * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(PulseTheme.waveGradient)
                        .frame(width: max(8, geo.size.width * displayedQuality))
                }
            }
            .frame(height: 8)
        }
        .frame(width: 150)
    }

    private var waveform: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Chart {
                ForEach(Array(engine.waveform.enumerated()), id: \.offset) { idx, val in
                    LineMark(
                        x: .value("t", idx),
                        y: .value("s", Double(val))
                    )
                    .foregroundStyle(PulseTheme.waveGradient)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
            .frame(height: 120)
            .padding(.horizontal, 4)
        }
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tips for a clean read", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            bullet("Cover the back camera and flash gently; avoid pressing too hard.")
            bullet("Hold still for the full minute; movement is the main cause of low signal quality.")
            bullet("Rest before measuring; avoid coffee or sprinting right before a resting read.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PulseTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PulseTheme.stroke))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(PulseTheme.accent).frame(width: 6, height: 6).padding(.top, 6)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func toggleMeasure() {
        if isMeasuring {
            completeMeasurement(cancelled: true)
        } else {
            #if targetEnvironment(simulator)
            return
            #else
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                beginMeasurement()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    DispatchQueue.main.async {
                        if ok { beginMeasurement() } else { showDenied = true }
                    }
                }
            default:
                showDenied = true
            }
            #endif
        }
    }

    private func beginMeasurement() {
        sessionMessage = nil
        latestReading = nil
        engine.start()
        isMeasuring = true
        startDate = .now
        progress = 0
        secondsLeft = Int(captureDuration)
    }

    private func completeMeasurement(cancelled: Bool = false) {
        guard isMeasuring else { return }
        isMeasuring = false
        startDate = nil
        progress = cancelled ? 0 : 1
        secondsLeft = cancelled ? Int(captureDuration) : 0

        if cancelled {
            sessionMessage = .cancelled
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                engine.resetBuffers()
            }
            return
        }

        engine.finalizeAndStop { bpm, quality in
            guard let bpm, quality >= MeasurementResultResolver.finalQualityThreshold else {
                sessionMessage = .lowSignal
                latestReading = nil
                progress = 0
                secondsLeft = Int(captureDuration)
                engine.resetBuffers()
                return
            }
            let reading = HeartReading(
                bpm: bpm,
                quality: quality,
                durationSeconds: Int(MeasurementConstants.captureDurationSeconds)
            )
            history.add(reading)
            latestReading = reading
            sessionMessage = nil
            successHaptic.notificationOccurred(.success)

            if settings.saveToHealth {
                Task {
                    _ = await healthKit.saveHeartRate(bpm: Double(bpm), at: reading.date)
                }
            }

            engine.resetBuffers()
        }
    }
}

struct PulseReadingInsight {
    let badge: String
    let title: String
    let detail: String
    let suggestion: String
    let tint: Color

    static func reading(for bpm: Int) -> PulseReadingInsight {
        switch bpm {
        case ..<50:
            return PulseReadingInsight(
                badge: "Low pulse",
                title: "Lower than a typical resting pulse",
                detail: "This can happen during deep rest or in very fit people, but it is worth a second check if this feels unusual for you.",
                suggestion: "Sit quietly and repeat once more. If readings stay low for you or you feel weak, dizzy, or faint, seek medical advice.",
                tint: PulseTheme.accent2
            )
        case 50..<60:
            return PulseReadingInsight(
                badge: "Calm pulse",
                title: "On the lower side of a resting pulse",
                detail: "A slower resting pulse can be normal, especially if you are relaxed or physically fit.",
                suggestion: "Use repeated readings in similar conditions to learn your personal baseline rather than judging one scan in isolation.",
                tint: PulseTheme.accent
            )
        case 60...100:
            return PulseReadingInsight(
                badge: "Typical resting pulse",
                title: "Within a common resting range",
                detail: "The American Heart Association notes that a normal resting heart rate for many adults falls between 60 and 100 BPM.",
                suggestion: "The most useful pattern comes from repeat scans at the same time of day and in the same calm posture.",
                tint: PulseTheme.success
            )
        case 101...120:
            return PulseReadingInsight(
                badge: "High resting pulse",
                title: "Higher than a typical resting pulse",
                detail: "Stress, movement, caffeine, heat, or an imperfect finger seal can push a resting read upward.",
                suggestion: "Rest for a few minutes, hydrate, and repeat while staying fully still. If it keeps happening at rest, talk with a clinician.",
                tint: PulseTheme.caution
            )
        default:
            return PulseReadingInsight(
                badge: "Very high resting pulse",
                title: "Quite elevated for a calm reading",
                detail: "Motion can inflate a camera-based scan, but a true resting pulse this high deserves extra attention.",
                suggestion: "Repeat once after resting quietly. If it stays high or you feel chest pain, shortness of breath, dizziness, or faintness, seek urgent care.",
                tint: PulseTheme.coral
            )
        }
    }
}

private struct SessionMessage {
    let title: String
    let detail: String
    let icon: String
    let tint: Color

    static var cancelled: SessionMessage {
        SessionMessage(
            title: "Session stopped",
            detail: "No reading was saved. Start again when your hand is steady and the camera is fully covered.",
            icon: "pause.circle.fill",
            tint: .orange
        )
    }

    static var lowSignal: SessionMessage {
        SessionMessage(
            title: "Signal was too low",
            detail: "Try again with the rear camera and LED fully covered, a relaxed grip, warm hands, and less movement during the full minute.",
            icon: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }

    static func saved(bpm: Int, quality: Double) -> SessionMessage {
        SessionMessage(
            title: "\(bpm) BPM saved",
            detail: "Signal quality \(Int(quality * 100))%. Use trends over time rather than one reading for wellness awareness.",
            icon: "checkmark.circle.fill",
            tint: PulseTheme.accent
        )
    }
}

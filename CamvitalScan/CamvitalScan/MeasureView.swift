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

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let successHaptic = UINotificationFeedbackGenerator()

    private var captureDuration: TimeInterval { MeasurementConstants.captureDurationSeconds }

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Optical pulse")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("One guided 60-second capture, then a refined BPM from the full recording.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            Text("Session = 1 minute (60 seconds), not 60 minutes—continuous hour-long flash PPG is not supported.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if targetEnvironment(simulator)
    private var simulatorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(PulseTheme.accent)
            Text("Simulator has no camera. Build on a physical iPhone to measure real heart rate.")
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
            if isMeasuring {
                Text("Remaining \(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(PulseTheme.accent)
            } else {
                Text("Session: 1:00")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
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
                    Text(engine.bpm.map { "\($0)" } ?? "—")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))

                    qualityBar

                    if let bpm = engine.bpm {
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

            Text("Final BPM uses the whole minute (skips the first few seconds for settle-in).")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            waveform

            Button(action: toggleMeasure) {
                Text(isMeasuring ? "Stop" : "Start 1-minute measurement")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isMeasuring ? Color.red.opacity(0.85) : PulseTheme.accent.opacity(0.9))
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

    private var qualityBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Signal")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("\(Int(engine.quality * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(PulseTheme.waveGradient)
                        .frame(width: max(8, geo.size.width * engine.quality))
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
            bullet("Cover the back camera and flash gently—don’t press too hard.")
            bullet("Hold still for the full minute; motion is the main enemy of clean PPG.")
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
        secondsLeft = Int(captureDuration)

        if cancelled {
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                engine.resetBuffers()
            }
            return
        }

        engine.finalizeAndStop { bpm, quality in
            guard let bpm, quality >= 0.22 else {
                engine.resetBuffers()
                return
            }
            let reading = HeartReading(
                bpm: bpm,
                quality: quality,
                durationSeconds: Int(MeasurementConstants.captureDurationSeconds)
            )
            history.add(reading)
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

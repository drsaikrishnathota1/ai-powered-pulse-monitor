import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            ZStack {
                PulseTheme.screenBackground.ignoresSafeArea()

                if history.readings.isEmpty {
                    ContentUnavailableView(
                        "No readings yet",
                        systemImage: "heart.text.square",
                        description: Text("Finish a measurement on the Measure tab to build your timeline.")
                    )
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    List {
                        summarySection
                        trendSection

                        ForEach(history.readings) { r in
                            readingRow(r)
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                        .onDelete(perform: history.delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
        }
    }

    private var trendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pulse trend", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(history.readings.count) scans")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Chart {
                    ForEach(Array(history.readings.reversed())) { reading in
                        LineMark(
                            x: .value("Date", reading.date),
                            y: .value("BPM", reading.bpm)
                        )
                        .foregroundStyle(PulseTheme.waveGradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", reading.date),
                            y: .value("BPM", reading.bpm)
                        )
                        .foregroundStyle(PulseTheme.accent)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(height: 150)

                Text("Use repeated readings in similar conditions to understand your personal wellness pattern.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(14)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PulseTheme.cardStrong))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PulseTheme.stroke))
        }
    }

    private func readingRow(_ reading: HeartReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(reading.bpm)")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                Text("BPM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                let zone = PulseHeartZone.zone(for: reading.bpm, age: settings.age)
                Text(zone.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                Label("\(Int(reading.quality * 100))%", systemImage: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer()

                Text(reading.durationSeconds >= 60 ? "1 min" : "\(reading.durationSeconds)s")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 6)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                summaryTile(
                    title: "Latest",
                    value: "\(history.readings.first?.bpm ?? 0)",
                    unit: "BPM",
                    icon: "heart.fill"
                )

                summaryTile(
                    title: "Average",
                    value: "\(averageBPM)",
                    unit: "BPM",
                    icon: "chart.line.uptrend.xyaxis"
                )

                summaryTile(
                    title: "Best signal",
                    value: "\(bestQuality)",
                    unit: "%",
                    icon: "waveform.path"
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private func summaryTile(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(PulseTheme.accent)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseTheme.stroke))
    }

    private var averageBPM: Int {
        guard !history.readings.isEmpty else { return 0 }
        let total = history.readings.reduce(0) { $0 + $1.bpm }
        return Int((Double(total) / Double(history.readings.count)).rounded())
    }

    private var bestQuality: Int {
        Int((history.readings.map(\.quality).max() ?? 0) * 100)
    }
}

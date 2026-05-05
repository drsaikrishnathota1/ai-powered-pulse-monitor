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

                        ForEach(history.readings) { r in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(r.bpm) BPM")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(r.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                HStack(spacing: 10) {
                                    Text(r.durationSeconds >= 60 ? "1 min" : "\(r.durationSeconds)s")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.08)))
                                    Text("Quality \(Int(r.quality * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
                                    Spacer()
                                    let zone = PulseHeartZone.zone(for: r.bpm, age: settings.age)
                                    Text(zone.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
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

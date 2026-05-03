import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var readings: [HeartReading] = []

    private let key = "pulseprime.readings.v2"

    init(seedReadings: [HeartReading]? = nil) {
        if let seedReadings {
            readings = seedReadings
        } else {
            load()
        }
    }

    func add(_ reading: HeartReading) {
        readings.insert(reading, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        readings.remove(atOffsets: offsets)
        save()
    }

    func delete(_ reading: HeartReading) {
        readings.removeAll { $0.id == reading.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([HeartReading].self, from: data) {
            readings = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

import Foundation

/// One guided capture length (seconds). Single mode: full 60-second read.
enum MeasurementConstants {
    static let captureDurationSeconds: TimeInterval = 60
}

struct HeartReading: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var bpm: Int
    var quality: Double
    /// Length of the capture window (seconds); new readings use 60.
    var durationSeconds: Int
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        bpm: Int,
        quality: Double,
        durationSeconds: Int = Int(MeasurementConstants.captureDurationSeconds),
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.bpm = bpm
        self.quality = quality
        self.durationSeconds = durationSeconds
        self.note = note
    }
}

struct MeasurementResolution {
    let bpm: Int?
    let quality: Double
    let usedLiveFallback: Bool
}

enum MeasurementResultResolver {
    static let finalQualityThreshold = 0.22
    static let liveFallbackQualityThreshold = 0.32

    static func resolve(
        finalBPM: Int?,
        finalQuality: Double,
        liveFallbackBPM: Int?,
        liveFallbackQuality: Double
    ) -> MeasurementResolution {
        if let finalBPM, finalQuality >= finalQualityThreshold {
            return MeasurementResolution(bpm: finalBPM, quality: finalQuality, usedLiveFallback: false)
        }

        guard let liveFallbackBPM, liveFallbackQuality >= liveFallbackQualityThreshold else {
            return MeasurementResolution(bpm: finalBPM, quality: finalQuality, usedLiveFallback: false)
        }

        let fallbackQuality = max(finalQuality, min(0.75, liveFallbackQuality * 0.92))
        return MeasurementResolution(bpm: liveFallbackBPM, quality: fallbackQuality, usedLiveFallback: true)
    }
}

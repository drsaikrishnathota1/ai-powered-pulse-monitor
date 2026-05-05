import XCTest
@testable import CamvitalScan

final class SignalProcessorTests: XCTestCase {

    func testMeasurementCaptureDurationIs60Seconds() {
        XCTAssertEqual(MeasurementConstants.captureDurationSeconds, 60, accuracy: 0.001)
    }

    func testSmoothPreservesCount() {
        let input = (0..<20).map { Double($0) }
        let out = SignalProcessor.smooth(input, window: 5)
        XCTAssertEqual(out.count, input.count)
    }

    func testFinalEstimateSynthetic72Bpm() {
        let fps = 30.0
        let duration = 65.0
        let count = Int(duration * fps)
        var samples: [Double] = []
        var times: [Double] = []
        let beatFreqHz = 72.0 / 60.0
        for i in 0..<count {
            let t = Double(i) / fps
            times.append(t)
            let phase = 2 * Double.pi * beatFreqHz * t
            samples.append(sin(phase) + 0.02 * sin(phase * 3.7))
        }

        let estimate = SignalProcessor.finalEstimate(
            samples: samples,
            times: times,
            estimatedFPS: fps
        )

        let bpm = estimate.bpm
        let quality = estimate.quality
        XCTAssertNotNil(bpm, "Expected BPM from synthetic 72 bpm sine train")
        XCTAssertGreaterThan(quality, 0.25, "Expected non-trivial quality on clean synthetic signal")
        if let bpm {
            XCTAssertEqual(bpm, 72, accuracy: 8, "Median BPM should be near ground truth 72")
        }
    }

    func testFinalEstimateRejectsWhiteNoise() {
        let fps = 30.0
        let duration = 65.0
        let count = Int(duration * fps)
        var rng = SeededGenerator(seed: 42)
        let samples = (0..<count).map { _ in Double.random(in: -1...1, using: &rng) }
        let times = (0..<count).map { Double($0) / fps }

        let estimate = SignalProcessor.finalEstimate(
            samples: samples,
            times: times,
            estimatedFPS: fps
        )

        XCTAssertNil(estimate.bpm, "Random noise should not be accepted as a heart-rate reading")
        XCTAssertLessThan(estimate.quality, 0.35, "Random noise should produce low signal quality")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}

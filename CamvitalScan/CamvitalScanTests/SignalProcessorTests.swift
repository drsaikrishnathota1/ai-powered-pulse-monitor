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
        let signal = makeSyntheticPPG(bpm: 72, fps: fps, duration: duration)

        let estimate = SignalProcessor.finalEstimate(
            samples: signal.samples,
            times: signal.times,
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

    func testFinalEstimateUsesTimestampCadenceWhenFPSHintIsSkewed() {
        let actualFPS = 30.0
        let signal = makeSyntheticPPG(bpm: 78, fps: actualFPS, duration: 65.0, harmonic: 0.12)

        let estimate = SignalProcessor.finalEstimate(
            samples: signal.samples,
            times: signal.times,
            estimatedFPS: 22.0
        )

        XCTAssertNotNil(estimate.bpm, "Expected BPM even when the caller's FPS estimate is skewed")
        XCTAssertGreaterThanOrEqual(estimate.quality, 0.22, "Valid signal should pass the save threshold")
        if let bpm = estimate.bpm {
            XCTAssertEqual(bpm, 78, accuracy: 8)
        }
    }

    func testFinalEstimateAcceptsStableSlowerPulse() {
        let signal = makeSyntheticPPG(bpm: 54, fps: 30, duration: 65.0, harmonic: 0.08)

        let estimate = SignalProcessor.finalEstimate(
            samples: signal.samples,
            times: signal.times,
            estimatedFPS: 30
        )

        XCTAssertNotNil(estimate.bpm, "Stable slower pulse should not be rejected as low signal")
        XCTAssertGreaterThanOrEqual(estimate.quality, 0.22, "Stable slower pulse should pass the save threshold")
        if let bpm = estimate.bpm {
            XCTAssertEqual(bpm, 54, accuracy: 8)
        }
    }

    func testFinalEstimateAcceptsNoisyRhythmicSignal() {
        let signal = makeNoisyPPG(bpm: 88, fps: 30, duration: 65.0)

        let estimate = SignalProcessor.finalEstimate(
            samples: signal.samples,
            times: signal.times,
            estimatedFPS: 30
        )

        XCTAssertNotNil(estimate.bpm, "Noisy but rhythmic PPG should not always fail as low signal")
        XCTAssertGreaterThanOrEqual(estimate.quality, 0.22)
        if let bpm = estimate.bpm {
            XCTAssertEqual(bpm, 88, accuracy: 10)
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

    private func makeSyntheticPPG(
        bpm: Double,
        fps: Double,
        duration: Double,
        harmonic: Double = 0.02
    ) -> (samples: [Double], times: [Double]) {
        let count = Int(duration * fps)
        var samples: [Double] = []
        var times: [Double] = []
        let beatFreqHz = bpm / 60.0
        for i in 0..<count {
            let t = Double(i) / fps
            times.append(t)
            let phase = 2 * Double.pi * beatFreqHz * t
            samples.append(sin(phase) + harmonic * sin(phase * 3.7))
        }
        return (samples, times)
    }

    private func makeNoisyPPG(bpm: Double, fps: Double, duration: Double) -> (samples: [Double], times: [Double]) {
        let count = Int(duration * fps)
        var rng = SeededGenerator(seed: 88)
        var samples: [Double] = []
        var times: [Double] = []
        let beatFreqHz = bpm / 60.0

        for i in 0..<count {
            let t = Double(i) / fps
            times.append(t)
            let phase = 2 * Double.pi * beatFreqHz * t
            let pulse = 0.03 * (sin(phase) + 0.25 * sin(2.0 * phase + 0.8))
            let drift = 0.01 * sin(2.0 * Double.pi * t / 12.0)
            let noise = Double.random(in: -0.01...0.01, using: &rng)
            let dropout = i > 0 && i % 37 == 0 ? -pulse : 0
            samples.append(0.4 + pulse + drift + noise + dropout)
        }

        return (samples, times)
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

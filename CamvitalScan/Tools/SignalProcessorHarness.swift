import Foundation

// Minimal CLI harness to sanity-check SignalProcessor without a device/simulator.
//
// Run from repo root:
//   swiftc CamvitalScan/CamvitalScan/SignalProcessor.swift CamvitalScan/Tools/SignalProcessorHarness.swift -o .tmp/signal_harness
//   ./.tmp/signal_harness

@inline(__always)
private func gaussianNoise(std: Double) -> Double {
    // Box-Muller
    let u1 = max(Double.random(in: 0..<1), 1e-12)
    let u2 = Double.random(in: 0..<1)
    let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * Double.pi * u2)
    return z0 * std
}

private struct SyntheticCase {
    let name: String
    let bpm: Double
    let fps: Double
    let seconds: Double
    let dc: Double
    let ac: Double
    let drift: Double
    let noiseStd: Double
    let dropoutEveryN: Int?
}

private func generatePPG(_ c: SyntheticCase) -> (samples: [Double], times: [Double]) {
    let n = Int(c.seconds * c.fps)
    let dt = 1.0 / c.fps
    var samples: [Double] = []
    var times: [Double] = []
    samples.reserveCapacity(n)
    times.reserveCapacity(n)

    let w = 2.0 * Double.pi * (c.bpm / 60.0)
    for i in 0..<n {
        let t = Double(i) * dt
        let base = sin(w * t) + 0.25 * sin(2.0 * w * t + 0.8)
        let slowDrift = c.drift * sin(2.0 * Double.pi * t / 12.0)

        var v = c.dc + c.ac * base + slowDrift + gaussianNoise(std: c.noiseStd)
        if let k = c.dropoutEveryN, k > 0, (i % k) == 0, i > 0 {
            v = c.dc + slowDrift + gaussianNoise(std: c.noiseStd * 2.0)
        }
        samples.append(v)
        times.append(t)
    }
    return (samples, times)
}

@main
struct Main {
    static func main() {
        let cases: [SyntheticCase] = [
            .init(
                name: "Clean 72bpm",
                bpm: 72, fps: 30, seconds: 60,
                dc: 0.42, ac: 0.035, drift: 0.006, noiseStd: 0.004,
                dropoutEveryN: nil
            ),
            .init(
                name: "Noisy 88bpm",
                bpm: 88, fps: 30, seconds: 60,
                dc: 0.40, ac: 0.030, drift: 0.010, noiseStd: 0.010,
                dropoutEveryN: 37
            ),
            .init(
                name: "Low AC 65bpm",
                bpm: 65, fps: 30, seconds: 60,
                dc: 0.55, ac: 0.012, drift: 0.006, noiseStd: 0.006,
                dropoutEveryN: 53
            ),
        ]

        print("SignalProcessor harness (finalEstimate)")
        for c in cases {
            let data = generatePPG(c)
            let estimate = SignalProcessor.finalEstimate(samples: data.samples, times: data.times, estimatedFPS: c.fps)
            let got = estimate.bpm.map(String.init) ?? "nil"
            let q = String(format: "%.3f", estimate.quality)
            print("[\(c.name)] expected≈\(Int(round(c.bpm))) got=\(got) quality=\(q)")
        }
    }
}

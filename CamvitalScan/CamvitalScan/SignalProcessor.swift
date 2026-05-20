import Foundation

enum SignalProcessor {
    private static let minimumBPM = 42.0
    private static let maximumBPM = 180.0

    struct Estimate {
        let bpm: Int?
        let quality: Double
    }

    /// Moving average (simple).
    static func smooth(_ values: [Double], window: Int) -> [Double] {
        guard !values.isEmpty, window > 1 else { return values }
        let w = min(window, values.count)
        var out = [Double](repeating: 0, count: values.count)
        var sum = 0.0
        for i in 0..<values.count {
            sum += values[i]
            if i >= w { sum -= values[i - w] }
            let c = min(i + 1, w)
            out[i] = sum / Double(c)
        }
        return out
    }

    /// Remove slow drift (high-pass-ish).
    static func detrend(_ values: [Double], baselineWindow: Int) -> [Double] {
        guard values.count > baselineWindow else { return values }
        let baseline = smooth(values, window: baselineWindow)
        return zip(values, baseline).map { $0 - $1 }
    }

    /// Local maxima with minimum index spacing.
    static func peakIndices(_ signal: [Double], minDistance: Int, sensitivity: Double) -> [Int] {
        guard signal.count > 5 else { return [] }
        let mean = signal.reduce(0, +) / Double(signal.count)
        let variance = signal.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(signal.count - 1, 1))
        let std = sqrt(max(variance, 1e-6))
        let threshold = mean + sensitivity * std

        var peaks: [Int] = []
        var last = -minDistance
        for i in 1..<(signal.count - 1) {
            let v = signal[i]
            if v > threshold, v >= signal[i - 1], v > signal[i + 1], i - last >= minDistance {
                peaks.append(i)
                last = i
            }
        }
        return peaks
    }

    /// BPM from peak sample indices and timestamps (seconds).
    static func bpm(from peaks: [Int], times: [Double]) -> Double? {
        guard peaks.count >= 2, peaks.max() ?? 0 < times.count else { return nil }
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let a = peaks[i - 1]
            let b = peaks[i]
            guard a >= 0, b < times.count, b > a else { continue }
            let dt = times[b] - times[a]
            if dt > 0.25, dt < 2.0 { intervals.append(dt) }
        }
        guard !intervals.isEmpty else { return nil }
        intervals.sort()
        let mid = intervals[intervals.count / 2]
        return 60.0 / mid
    }

    /// 0...1 quality from signal stability and peak count reasonableness.
    static func quality(signal: [Double], sampleRate: Double, duration: Double) -> Double {
        guard signal.count > 30 else { return 0 }
        let mean = signal.reduce(0, +) / Double(signal.count)
        let std = sqrt(signal.map { pow($0 - mean, 2) }.reduce(0, +) / Double(signal.count))
        let amplitudeScore = min(1, std / 0.35)
        let peaks = peakIndices(detrend(signal, baselineWindow: Int(sampleRate)), minDistance: Int(sampleRate * 0.35), sensitivity: 0.35)
        let rhythm = rhythmScore(from: peaks, sampleRate: sampleRate, duration: duration)
        return max(0, min(1, 0.35 * amplitudeScore + 0.65 * rhythm))
    }

    /// Live estimate from a shorter moving window. Returns nil unless the signal is plausible.
    static func liveEstimate(samples: [Double], times: [Double], estimatedFPS: Double) -> Estimate {
        estimate(samples: samples, times: times, estimatedFPS: estimatedFPS, warmupSeconds: 1.0, minimumSeconds: 10.0)
    }

    /// End-of-session BPM + quality using the full buffer (skips first ~5s for settle-in).
    static func finalEstimate(samples: [Double], times: [Double], estimatedFPS: Double) -> Estimate {
        estimate(samples: samples, times: times, estimatedFPS: estimatedFPS, warmupSeconds: 5.0, minimumSeconds: 18.0)
    }

    private static func estimate(
        samples: [Double],
        times: [Double],
        estimatedFPS: Double,
        warmupSeconds: Double,
        minimumSeconds: Double
    ) -> Estimate {
        let fps = sampleRate(from: times, fallback: estimatedFPS)
        guard samples.count == times.count, samples.count > Int(fps * minimumSeconds) else {
            return Estimate(bpm: nil, quality: 0)
        }

        let warmup = min(Int(fps * warmupSeconds), samples.count / 5)
        let s = Array(samples.dropFirst(warmup))
        let t = Array(times.dropFirst(warmup))
        guard s.count > Int(fps * max(6.0, minimumSeconds - warmupSeconds)) else {
            return Estimate(bpm: nil, quality: 0)
        }

        let baselineWin = min(Int(fps * 0.9), max(30, s.count / 8))
        let detrended = detrend(s, baselineWindow: baselineWin)
        let smoothed = smooth(detrended, window: 5)
        let minDist = max(8, Int(fps * 60.0 / maximumBPM * 0.82))
        let peaks = peakIndices(smoothed, minDistance: minDist, sensitivity: 0.25)

        let duration = (t.last ?? 0) - (t.first ?? 0)
        let qLegacy = quality(signal: smoothed, sampleRate: fps, duration: max(duration, 0.1))

        guard peaks.count >= 4 else {
            if let v = bpm(from: peaks, times: t), v > 38, v < 210 {
                return Estimate(bpm: Int(round(v)), quality: max(0, min(1, qLegacy * 0.45)))
            }
            return Estimate(bpm: nil, quality: qLegacy * 0.35)
        }

        var bpms: [Double] = []
        for i in 1..<peaks.count {
            let a = peaks[i - 1]
            let b = peaks[i]
            guard a >= 0, b < t.count, b > a else { continue }
            let dt = t[b] - t[a]
            if dt > 0.28, dt < 2.0 { bpms.append(60.0 / dt) }
        }

        let medianBpm: Double?
        if bpms.count >= 5 {
            bpms.sort()
            medianBpm = bpms[bpms.count / 2]
        } else if let v = bpm(from: peaks, times: t) {
            medianBpm = v
        } else {
            return Estimate(bpm: nil, quality: qLegacy * 0.45)
        }

        guard let med = medianBpm, med >= minimumBPM, med <= maximumBPM else {
            return Estimate(bpm: nil, quality: qLegacy * 0.35)
        }

        let bpmSpread: Double
        if bpms.count >= 5 {
            let sorted = bpms.sorted()
            let q1 = sorted[sorted.count / 4]
            let q3 = sorted[(sorted.count * 3) / 4]
            bpmSpread = max(0, q3 - q1)
        } else {
            bpmSpread = 6
        }

        let qStability = 1 - min(1, bpmSpread / max(med * 0.12, 2))
        let spectral = spectralEstimate(signal: smoothed, sampleRate: fps)

        let agreement: Double
        let agreementScore: Double
        if let spectralBPM = spectral.bpm {
            agreement = abs(spectralBPM - med)
            guard agreement <= 20 else {
                let q = max(0, min(1, 0.25 * qLegacy + 0.35 * spectral.dominance))
                let harmonicAgreement = min(abs(spectralBPM * 2 - med), abs(spectralBPM - med * 2))
                if harmonicAgreement <= 12, qLegacy >= 0.24 {
                    return Estimate(bpm: Int(round(med)), quality: max(q, 0.24))
                }
                let intervalFallbackQuality = max(
                    q,
                    min(0.52, 0.55 * qLegacy + 0.45 * qStability)
                )
                if qLegacy >= 0.32, qStability >= 0.45, spectral.dominance < 0.22 {
                    return Estimate(bpm: Int(round(med)), quality: intervalFallbackQuality)
                }
                return Estimate(bpm: nil, quality: q)
            }
            agreementScore = 1 - min(1, agreement / 14)
        } else {
            agreement = 14
            agreementScore = 0.35
        }
        let mean = s.reduce(0, +) / Double(s.count)
        let rawStd = sqrt(s.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(s.count - 1, 1)))
        let amplitudeScore = min(1, rawStd / 0.75)
        let spectralScore = spectral.bpm == nil ? 0.18 : spectral.dominance
        let finalQ = max(
            0,
            min(
                1,
                0.24 * qLegacy
                    + 0.28 * qStability
                    + 0.28 * spectralScore
                    + 0.10 * amplitudeScore
                    + 0.10 * agreementScore
            )
        )

        guard finalQ >= 0.18 else {
            return Estimate(bpm: nil, quality: finalQ)
        }

        let blended: Double
        if let spectralBPM = spectral.bpm {
            blended = 0.62 * med + 0.38 * spectralBPM
        } else {
            blended = med
        }
        return Estimate(bpm: Int(round(blended)), quality: finalQ)
    }

    private static func sampleRate(from times: [Double], fallback: Double) -> Double {
        guard times.count >= 2, let first = times.first, let last = times.last, last > first else {
            return min(max(fallback, 15), 120)
        }
        let measured = Double(times.count - 1) / (last - first)
        return min(max(measured, 15), 120)
    }

    private static func rhythmScore(from peaks: [Int], sampleRate: Double, duration: Double) -> Double {
        guard peaks.count >= 4, sampleRate > 0, duration > 0 else { return 0 }

        let intervals = zip(peaks.dropFirst(), peaks).compactMap { current, previous -> Double? in
            let seconds = Double(current - previous) / sampleRate
            return seconds > 0.28 && seconds < 2.0 ? seconds : nil
        }
        guard intervals.count >= 3 else { return 0 }

        let bpms = intervals.map { 60.0 / $0 }.sorted()
        let median = bpms[bpms.count / 2]
        guard median >= minimumBPM, median <= maximumBPM else { return 0 }

        let q1 = bpms[bpms.count / 4]
        let q3 = bpms[(bpms.count * 3) / 4]
        let stabilityScore = 1 - min(1, max(0, q3 - q1) / max(median * 0.15, 3))
        let expectedBeats = duration * median / 60.0
        let countScore = 1 - min(1, abs(Double(peaks.count) - expectedBeats) / max(expectedBeats * 0.45, 1))

        return max(0, min(1, 0.7 * stabilityScore + 0.3 * countScore))
    }

    private static func spectralEstimate(signal: [Double], sampleRate: Double) -> (bpm: Double?, dominance: Double) {
        guard signal.count > Int(sampleRate * 6), sampleRate > 0 else { return (nil, 0) }

        let mean = signal.reduce(0, +) / Double(signal.count)
        let centered = signal.map { $0 - mean }
        let maxLag = max(2, Int(sampleRate * 60.0 / minimumBPM))
        let minLag = max(1, Int(sampleRate * 60.0 / maximumBPM))
        guard maxLag > minLag, centered.count > maxLag + 2 else { return (nil, 0) }

        var bestLag = minLag
        var bestCorrelation = -Double.infinity
        var correlations: [Double] = []

        for lag in minLag...maxLag {
            var numerator = 0.0
            var leftEnergy = 0.0
            var rightEnergy = 0.0
            for i in lag..<centered.count {
                let a = centered[i]
                let b = centered[i - lag]
                numerator += a * b
                leftEnergy += a * a
                rightEnergy += b * b
            }
            let correlation = numerator / max(sqrt(leftEnergy * rightEnergy), 1e-9)
            correlations.append(correlation)
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        let positive = correlations.map { max(0, $0) }
        let average = positive.reduce(0, +) / Double(max(positive.count, 1))
        let dominance = max(0, min(1, (max(0, bestCorrelation) - average) / 0.30))
        let bpm = 60.0 * sampleRate / Double(bestLag)
        guard bpm >= minimumBPM, bpm <= maximumBPM, dominance > 0.04 else {
            return (nil, dominance)
        }
        return (bpm, dominance)
    }
}

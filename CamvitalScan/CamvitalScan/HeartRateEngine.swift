import AVFoundation
import Combine
import UIKit

/// Camera + torch PPG: green-channel mean from a center ROI, peak-based BPM.
final class HeartRateEngine: NSObject, ObservableObject {
    @Published var bpm: Int?
    @Published var isRunning = false
    @Published var waveform: [CGFloat] = []
    @Published var quality: Double = 0
    @Published var cameraError: String?
    @Published var torchWarmWarning = false

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "pulseprime.camera", qos: .userInitiated)
    private var device: AVCaptureDevice?

    private var samples: [Double] = []
    private var times: [Double] = []
    private var sessionStart: CFTimeInterval?
    private var frameCount = 0
    private var torchWatchdog: DispatchSourceTimer?
    /// ~2.5 minutes at 30 fps — enough for a full 60 s capture plus margin.
    private let maxSamples = 4500
    private let waveformDisplayCount = 220

    func start() {
        cameraError = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.samples.removeAll()
            self.times.removeAll()
            self.sessionStart = nil
            self.frameCount = 0
            DispatchQueue.main.async {
                self.bpm = nil
                self.quality = 0
                self.waveform = []
            }
            self.configureAndStart()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.tearDown()
        }
    }

    func resetBuffers() {
        queue.async { [weak self] in
            self?.samples.removeAll()
            self?.times.removeAll()
            self?.sessionStart = nil
            self?.frameCount = 0
            DispatchQueue.main.async {
                self?.bpm = nil
                self?.waveform = []
                self?.quality = 0
            }
        }
    }

    /// Stops the camera after computing BPM/quality from the full recorded buffer (best for a 60 s session).
    func finalizeAndStop(completion: @escaping (_ bpm: Int?, _ quality: Double) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil, 0) }
                return
            }
            let tEnd = CACurrentMediaTime()
            let fps: Double
            if let start = self.sessionStart, tEnd > start + 0.5, self.frameCount > 40 {
                fps = Double(self.frameCount) / (tEnd - start)
            } else {
                fps = 30
            }
            let fpsClamped = min(max(fps, 15), 120)
            let result = SignalProcessor.finalEstimate(
                samples: self.samples,
                times: self.times,
                estimatedFPS: fpsClamped
            )
            self.tearDown()
            DispatchQueue.main.async {
                completion(result.bpm, result.quality)
            }
        }
    }

    private func configureAndStart() {
        tearDown()

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.cameraError = "No back camera found." }
            session.commitConfiguration()
            return
        }
        self.device = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.cameraError = "Could not add camera input." }
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { self.cameraError = "Could not open camera." }
            return
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { self.cameraError = "Could not attach video output." }
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        do {
            try device.lockForConfiguration()
            let targetFrameDuration = CMTime(value: 1, timescale: 30)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && 30 <= $0.maxFrameRate }) {
                device.activeVideoMinFrameDuration = targetFrameDuration
                device.activeVideoMaxFrameDuration = targetFrameDuration
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.hasTorch, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: min(0.75, AVCaptureDevice.maxAvailableTorchLevel))
            }
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.cameraError = "Camera configuration failed." }
            tearDown()
            return
        }

        sessionStart = CACurrentMediaTime()
        session.startRunning()
        startTorchWatchdog()

        DispatchQueue.main.async {
            self.isRunning = true
            self.torchWarmWarning = true
        }
    }

    private func tearDown() {
        torchWatchdog?.cancel()
        torchWatchdog = nil
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for out in session.outputs {
            session.removeOutput(out)
        }
        session.commitConfiguration()

        if let device = device {
            try? device.lockForConfiguration()
            if device.hasTorch, device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        }
        device = nil
        samples.removeAll()
        times.removeAll()
        sessionStart = nil
        frameCount = 0

        DispatchQueue.main.async {
            self.isRunning = false
            self.torchWarmWarning = false
        }
    }

    private func startTorchWatchdog() {
        torchWatchdog?.cancel()
        guard let device, device.hasTorch, device.isTorchModeSupported(.on) else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.ensureTorchIsOn()
        }
        torchWatchdog = timer
        timer.resume()
    }

    private func ensureTorchIsOn() {
        guard let device, session.isRunning, device.hasTorch, device.isTorchModeSupported(.on) else { return }
        guard !device.isTorchActive || device.torchMode != .on else { return }

        do {
            try device.lockForConfiguration()
            try device.setTorchModeOn(level: min(0.75, AVCaptureDevice.maxAvailableTorchLevel))
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.cameraError = "LED flash could not stay on. Let the phone cool and try again."
            }
        }
    }

    private func appendSample(value: Double, t: Double) {
        samples.append(value)
        times.append(t)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
            times.removeFirst(times.count - maxSamples)
        }

        let fps: Double
        if let start = sessionStart, t > start {
            fps = Double(frameCount) / (t - start)
        } else {
            fps = 30
        }

        updateWaveform()
        estimateBPM(estimatedFPS: min(max(fps, 15), 120))
    }

    private func updateWaveform() {
        let tail = Array(samples.suffix(waveformDisplayCount))
        guard let minV = tail.min(), let maxV = tail.max(), maxV > minV else {
            DispatchQueue.main.async { self.waveform = tail.map { _ in 0.5 } }
            return
        }
        let norm = tail.map { CGFloat(($0 - minV) / (maxV - minV)) }
        DispatchQueue.main.async {
            self.waveform = norm
        }
    }

    private func estimateBPM(estimatedFPS: Double) {
        guard samples.count > Int(estimatedFPS * 4) else { return }

        let recentCount = min(samples.count, Int(estimatedFPS * 18))
        let recentSamples = Array(samples.suffix(recentCount))
        let recentTimes = Array(times.suffix(recentCount))
        let result = SignalProcessor.liveEstimate(
            samples: recentSamples,
            times: recentTimes,
            estimatedFPS: estimatedFPS
        )

        DispatchQueue.main.async {
            self.quality = result.quality
            if let b = result.bpm, result.quality >= 0.32 {
                self.bpm = b
            }
        }
    }
}

extension HeartRateEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        let t = CACurrentMediaTime()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let region = 96
        let cx = width / 2
        let cy = height / 2
        let x0 = max(0, cx - region / 2)
        let y0 = max(0, cy - region / 2)
        let x1 = min(width, x0 + region)
        let y1 = min(height, y0 + region)

        var greenSum: Double = 0
        var count = 0
        for y in y0..<y1 {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: x0, to: x1, by: 2) {
                let o = x * 4
                let b = Double(row[o])
                let g = Double(row[o + 1])
                let r = Double(row[o + 2])
                greenSum += 0.3 * r + 0.7 * g + 0.1 * b
                count += 1
            }
        }
        guard count > 0 else { return }
        appendSample(value: greenSum / Double(count), t: t)
    }
}

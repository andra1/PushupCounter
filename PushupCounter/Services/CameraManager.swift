import AVFoundation
import Vision
import Observation

@Observable
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    private(set) var cameraPermissionGranted = false
    private(set) var bodyDetected = false

    private let pushupDetector: PushupDetector
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.pushupcounter.video", qos: .userInitiated)

    init(pushupDetector: PushupDetector) {
        self.pushupDetector = pushupDetector
        super.init()
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraPermissionGranted = granted
        }
    }

    func setupSession() {
        guard cameraPermissionGranted else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    func startSession() {
        guard !session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

// MARK: - Video Frame Processing

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            DispatchQueue.main.async { [weak self] in
                self?.pushupDetector.processFrame(hipHeight: nil, elbowAngle: nil)
                self?.bodyDetected = false
            }
            return
        }

        let angle = extractElbowAngle(from: observation)

        DispatchQueue.main.async { [weak self] in
            self?.pushupDetector.processFrame(hipHeight: nil, elbowAngle: angle)
            self?.bodyDetected = angle != nil
        }
    }

    private func extractElbowAngle(from observation: VNHumanBodyPoseObservation) -> Double? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        let rightAngle = computeArmAngle(
            shoulder: points[.rightShoulder],
            elbow: points[.rightElbow],
            wrist: points[.rightWrist]
        )

        let leftAngle = computeArmAngle(
            shoulder: points[.leftShoulder],
            elbow: points[.leftElbow],
            wrist: points[.leftWrist]
        )

        switch (rightAngle, leftAngle) {
        case let (r?, l?):
            return (r + l) / 2.0
        case let (r?, nil):
            return r
        case let (nil, l?):
            return l
        case (nil, nil):
            return nil
        }
    }

    private func computeArmAngle(
        shoulder: VNRecognizedPoint?,
        elbow: VNRecognizedPoint?,
        wrist: VNRecognizedPoint?
    ) -> Double? {
        guard let shoulder, shoulder.confidence > 0.6,
              let elbow, elbow.confidence > 0.6,
              let wrist, wrist.confidence > 0.6 else {
            return nil
        }
        return AngleCalculator.angle(
            a: CGPoint(x: shoulder.location.x, y: shoulder.location.y),
            b: CGPoint(x: elbow.location.x, y: elbow.location.y),
            c: CGPoint(x: wrist.location.x, y: wrist.location.y)
        )
    }
}

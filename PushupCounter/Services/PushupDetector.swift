import Observation

enum PushupPhase: Equatable {
    case calibrating
    case up
    case down
    case unknown
}

@MainActor
@Observable
final class PushupDetector {
    private(set) var count: Int = 0
    private(set) var phase: PushupPhase = .calibrating
    private(set) var bodyDetected: Bool = false
    private(set) var baselineHeight: Float?
    private(set) var completedRepAngles: [RepAngle] = []

    private var calibrationSamples: [Float] = []
    private var pendingPhase: PushupPhase = .unknown
    private var consecutiveFrames: Int = 0

    // Per-rep angle tracking
    private var currentRepMinAngle: Double = .greatestFiniteMagnitude
    private var currentRepMaxAngle: Double = 0.0

    private let debounceThreshold = 3
    private let calibrationFrameCount = 10
    private let downDropThreshold: Float = 0.15
    private let upDropThreshold: Float = 0.05

    func processFrame(hipHeight: Float?, elbowAngle: Double?) {
        guard let hipHeight else {
            bodyDetected = false
            return
        }
        bodyDetected = true

        // Track elbow angle for current rep
        if let angle = elbowAngle {
            currentRepMinAngle = min(currentRepMinAngle, angle)
            currentRepMaxAngle = max(currentRepMaxAngle, angle)
        }

        // Calibration phase: collect samples to establish baseline
        if phase == .calibrating {
            calibrationSamples.append(hipHeight)
            if calibrationSamples.count >= calibrationFrameCount {
                baselineHeight = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
                phase = .unknown
            }
            return
        }

        guard let baseline = baselineHeight else { return }

        let drop = baseline - hipHeight

        let detected: PushupPhase
        if drop > downDropThreshold {
            detected = .down
        } else if drop < upDropThreshold {
            detected = .up
        } else {
            return // dead zone
        }

        if detected == pendingPhase {
            consecutiveFrames += 1
        } else {
            pendingPhase = detected
            consecutiveFrames = 1
        }

        if consecutiveFrames >= debounceThreshold && detected != phase {
            let previous = phase
            phase = detected
            if previous == .down && detected == .up {
                count += 1
                completedRepAngles.append(RepAngle(
                    minAngle: currentRepMinAngle == .greatestFiniteMagnitude ? 0.0 : currentRepMinAngle,
                    maxAngle: currentRepMaxAngle
                ))
                currentRepMinAngle = .greatestFiniteMagnitude
                currentRepMaxAngle = 0.0
            }
        }
    }

    func reset() {
        count = 0
        phase = .calibrating
        bodyDetected = false
        baselineHeight = nil
        calibrationSamples = []
        pendingPhase = .unknown
        consecutiveFrames = 0
        completedRepAngles = []
        currentRepMinAngle = .greatestFiniteMagnitude
        currentRepMaxAngle = 0.0
    }
}

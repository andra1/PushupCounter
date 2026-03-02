import Observation

enum PushupPhase: Equatable {
    case up
    case down
    case unknown
}

@MainActor
@Observable
final class PushupDetector {
    private(set) var count: Int = 0
    private(set) var phase: PushupPhase = .unknown
    private(set) var bodyDetected: Bool = false

    private var pendingPhase: PushupPhase = .unknown
    private var consecutiveFrames: Int = 0

    private let debounceThreshold = 3
    private let downAngleThreshold: Double = 90
    private let upAngleThreshold: Double = 160

    func processAngle(_ angle: Double?) {
        guard let angle else {
            bodyDetected = false
            return
        }
        bodyDetected = true

        let detected: PushupPhase
        if angle < downAngleThreshold {
            detected = .down
        } else if angle > upAngleThreshold {
            detected = .up
        } else {
            return
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
            }
        }
    }

    func reset() {
        count = 0
        phase = .unknown
        bodyDetected = false
        pendingPhase = .unknown
        consecutiveFrames = 0
    }
}

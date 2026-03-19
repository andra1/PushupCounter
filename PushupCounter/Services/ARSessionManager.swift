import ARKit
import RealityKit
import Observation

@Observable
final class ARSessionManager: NSObject {
    let arView = ARView(frame: .zero)
    private(set) var bodyTrackingSupported: Bool
    private(set) var bodyDetected: Bool = false

    private let pushupDetector: PushupDetector

    init(pushupDetector: PushupDetector) {
        self.pushupDetector = pushupDetector
        self.bodyTrackingSupported = ARBodyTrackingConfiguration.isSupported
        super.init()
        arView.session.delegate = self
    }

    func startSession() {
        guard bodyTrackingSupported else { return }
        let configuration = ARBodyTrackingConfiguration()
        configuration.frameSemantics = .bodyDetection
        arView.session.run(configuration)
    }

    func pauseSession() {
        arView.session.pause()
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let bodyAnchor = anchors.compactMap({ $0 as? ARBodyAnchor }).first else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pushupDetector.processFrame(hipHeight: nil, elbowAngle: nil)
                self.bodyDetected = false
            }
            return
        }

        let hipHeight = bodyAnchor.transform.columns.3.y

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // TODO: Extract elbow angle in Task 4
            self.pushupDetector.processFrame(hipHeight: hipHeight, elbowAngle: nil)
            self.bodyDetected = true
        }
    }
}

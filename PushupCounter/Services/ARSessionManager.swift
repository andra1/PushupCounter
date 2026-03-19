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
        let elbowAngle = Self.extractElbowAngle(from: bodyAnchor.skeleton)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pushupDetector.processFrame(hipHeight: hipHeight, elbowAngle: elbowAngle)
            self.bodyDetected = true
        }
    }

    private static func extractElbowAngle(from skeleton: ARSkeleton3D) -> Double? {
        let leftAngle = elbowAngle(
            from: skeleton,
            shoulder: "left_shoulder_1_joint",
            elbow: "left_forearm_joint",
            wrist: "left_hand_joint"
        )
        let rightAngle = elbowAngle(
            from: skeleton,
            shoulder: "right_shoulder_1_joint",
            elbow: "right_forearm_joint",
            wrist: "right_hand_joint"
        )

        switch (leftAngle, rightAngle) {
        case let (l?, r?): return (l + r) / 2.0
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private static func elbowAngle(
        from skeleton: ARSkeleton3D,
        shoulder: String,
        elbow: String,
        wrist: String
    ) -> Double? {
        let shoulderIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: shoulder))
        let elbowIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: elbow))
        let wristIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: wrist))

        guard shoulderIdx != NSNotFound,
              elbowIdx != NSNotFound,
              wristIdx != NSNotFound
        else { return nil }

        let shoulderTransform = skeleton.jointModelTransforms[shoulderIdx]
        let elbowTransform = skeleton.jointModelTransforms[elbowIdx]
        let wristTransform = skeleton.jointModelTransforms[wristIdx]

        // Check for untracked joints (identity matrix)
        let identity = simd_float4x4(1.0)
        if shoulderTransform == identity || elbowTransform == identity || wristTransform == identity {
            return nil
        }

        // Project 3D to 2D (X, Y plane — sagittal)
        let shoulderPt = CGPoint(x: CGFloat(shoulderTransform.columns.3.x), y: CGFloat(shoulderTransform.columns.3.y))
        let elbowPt = CGPoint(x: CGFloat(elbowTransform.columns.3.x), y: CGFloat(elbowTransform.columns.3.y))
        let wristPt = CGPoint(x: CGFloat(wristTransform.columns.3.x), y: CGFloat(wristTransform.columns.3.y))

        return AngleCalculator.angle(a: shoulderPt, b: elbowPt, c: wristPt)
    }
}

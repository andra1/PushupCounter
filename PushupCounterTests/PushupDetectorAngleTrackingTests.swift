import XCTest
@testable import PushupCounter

@MainActor
final class PushupDetectorAngleTrackingTests: XCTestCase {

    private var detector: PushupDetector!

    private let baseline: Float = 1.0
    private let upHeight: Float = 1.0
    private let downHeight: Float = 0.8

    override func setUp() {
        detector = PushupDetector()
    }

    private func calibrate() {
        for _ in 0..<10 {
            detector.processFrame(hipHeight: baseline, elbowAngle: 170.0)
        }
    }

    private func feedFrame(hipHeight: Float, elbowAngle: Double?, frames: Int) {
        for _ in 0..<frames {
            detector.processFrame(hipHeight: hipHeight, elbowAngle: elbowAngle)
        }
    }

    func testInitial_completedRepAnglesIsEmpty() {
        XCTAssertTrue(detector.completedRepAngles.isEmpty)
    }

    func testOneRep_recordsMinAndMaxAngles() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: 100.0, frames: 1)
        feedFrame(hipHeight: downHeight, elbowAngle: 85.0, frames: 1)
        feedFrame(hipHeight: downHeight, elbowAngle: 90.0, frames: 1)
        feedFrame(hipHeight: upHeight, elbowAngle: 165.0, frames: 3)

        XCTAssertEqual(detector.completedRepAngles.count, 1)
        XCTAssertEqual(detector.completedRepAngles[0].minAngle, 85.0)
        XCTAssertEqual(detector.completedRepAngles[0].maxAngle, 170.0)
    }

    func testTwoReps_recordsBothSeparately() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: 80.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 165.0, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: 95.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 155.0, frames: 3)

        XCTAssertEqual(detector.completedRepAngles.count, 2)
        XCTAssertEqual(detector.completedRepAngles[0].minAngle, 80.0)
        XCTAssertEqual(detector.completedRepAngles[1].minAngle, 95.0)
    }

    func testNilElbowAngle_doesNotCrash() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: nil, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: nil, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: nil, frames: 3)

        XCTAssertEqual(detector.count, 1)
        XCTAssertEqual(detector.completedRepAngles.count, 1)
    }

    func testReset_clearsCompletedRepAngles() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: 80.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        XCTAssertEqual(detector.completedRepAngles.count, 1)

        detector.reset()
        XCTAssertTrue(detector.completedRepAngles.isEmpty)
    }
}

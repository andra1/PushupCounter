import XCTest
@testable import PushupCounter

@MainActor
final class PushupDetectorTests: XCTestCase {

    private var detector: PushupDetector!

    // Test constants
    private let baseline: Float = 1.0
    private let upHeight: Float = 1.0       // at baseline (drop = 0)
    private let downHeight: Float = 0.8     // drop = 0.2m (> 0.15 threshold)
    private let midHeight: Float = 0.92     // drop = 0.08m (in dead zone 0.05–0.15)

    override func setUp() {
        detector = PushupDetector()
    }

    // MARK: - Initial State

    func testInitialState_countIsZero() {
        XCTAssertEqual(detector.count, 0)
    }

    func testInitialState_phaseIsCalibrating() {
        XCTAssertEqual(detector.phase, .calibrating)
    }

    func testInitialState_bodyNotDetected() {
        XCTAssertFalse(detector.bodyDetected)
    }

    // MARK: - Calibration

    func testCalibration_startsInCalibratingPhase() {
        XCTAssertEqual(detector.phase, .calibrating)
        XCTAssertNil(detector.baselineHeight)
    }

    func testCalibration_completesAfterTenFrames() {
        calibrate(at: baseline)
        XCTAssertNotNil(detector.baselineHeight)
        XCTAssertNotEqual(detector.phase, .calibrating)
    }

    func testCalibration_setsCorrectBaseline() {
        calibrate(at: baseline)
        XCTAssertEqual(detector.baselineHeight!, baseline, accuracy: 0.001)
    }

    func testCalibration_nineFramesStillCalibrating() {
        for _ in 0..<9 {
            detector.processFrame(hipHeight: baseline, elbowAngle: nil)
        }
        XCTAssertEqual(detector.phase, .calibrating)
        XCTAssertNil(detector.baselineHeight)
    }

    func testReset_clearsCalibration() {
        calibrate(at: baseline)
        XCTAssertNotNil(detector.baselineHeight)

        detector.reset()
        XCTAssertEqual(detector.phase, .calibrating)
        XCTAssertNil(detector.baselineHeight)
    }

    // MARK: - Body Detection

    func testNilHeight_bodyNotDetected() {
        calibrate(at: baseline)
        detector.processFrame(hipHeight: nil, elbowAngle: nil)
        XCTAssertFalse(detector.bodyDetected)
    }

    func testValidHeight_bodyDetected() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 1)
        XCTAssertTrue(detector.bodyDetected)
    }

    // MARK: - Phase Transitions (with debounce = 3 frames)

    func testHighHeight_transitionsToUp() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    func testLowHeight_transitionsToDown() {
        calibrate(at: baseline)
        feedHeight(downHeight, frames: 3)
        XCTAssertEqual(detector.phase, .down)
    }

    func testMidHeight_noTransition() {
        calibrate(at: baseline)
        feedHeight(midHeight, frames: 10)
        XCTAssertEqual(detector.phase, .unknown)
    }

    // MARK: - Debounce

    func testSingleFrame_noTransition() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 1)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testTwoFrames_noTransition() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 2)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testThreeFrames_transitionsToUp() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    // MARK: - Counting

    func testDownToUp_incrementsCount() {
        calibrate(at: baseline)
        feedHeight(downHeight, frames: 3)
        XCTAssertEqual(detector.phase, .down)
        feedHeight(upHeight, frames: 3)
        XCTAssertEqual(detector.phase, .up)
        XCTAssertEqual(detector.count, 1)
    }

    func testUpToDown_doesNotIncrementCount() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)
        XCTAssertEqual(detector.phase, .up)
        feedHeight(downHeight, frames: 3)
        XCTAssertEqual(detector.phase, .down)
        XCTAssertEqual(detector.count, 0)
    }

    func testFullPushupCycle_countsOne() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)   // UP
        feedHeight(downHeight, frames: 3) // DOWN
        feedHeight(upHeight, frames: 3)   // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    func testTwoPushups() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)   // UP
        feedHeight(downHeight, frames: 3) // DOWN
        feedHeight(upHeight, frames: 3)   // UP → count = 1
        feedHeight(downHeight, frames: 3) // DOWN
        feedHeight(upHeight, frames: 3)   // UP → count = 2
        XCTAssertEqual(detector.count, 2)
    }

    func testMidHeightBetweenPhases_doesNotCount() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)   // UP
        feedHeight(downHeight, frames: 3) // DOWN
        feedHeight(midHeight, frames: 5)  // mid-range, no transition
        feedHeight(upHeight, frames: 3)   // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    // MARK: - Reset

    func testReset_clearsEverything() {
        calibrate(at: baseline)
        feedHeight(upHeight, frames: 3)
        feedHeight(downHeight, frames: 3)
        feedHeight(upHeight, frames: 3)
        XCTAssertEqual(detector.count, 1)

        detector.reset()
        XCTAssertEqual(detector.count, 0)
        XCTAssertEqual(detector.phase, .calibrating)
        XCTAssertFalse(detector.bodyDetected)
        XCTAssertNil(detector.baselineHeight)
    }

    // MARK: - Helpers

    private func calibrate(at height: Float) {
        for _ in 0..<10 {
            detector.processFrame(hipHeight: height, elbowAngle: nil)
        }
    }

    private func feedHeight(_ height: Float, frames: Int) {
        for _ in 0..<frames {
            detector.processFrame(hipHeight: height, elbowAngle: nil)
        }
    }
}

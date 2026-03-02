import XCTest
@testable import PushupCounter

@MainActor
final class PushupDetectorTests: XCTestCase {

    private var detector: PushupDetector!

    override func setUp() {
        detector = PushupDetector()
    }

    // MARK: - Initial State

    func testInitialState_countIsZero() {
        XCTAssertEqual(detector.count, 0)
    }

    func testInitialState_phaseIsUnknown() {
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testInitialState_bodyNotDetected() {
        XCTAssertFalse(detector.bodyDetected)
    }

    // MARK: - Body Detection

    func testNilAngle_bodyNotDetected() {
        detector.processAngle(nil)
        XCTAssertFalse(detector.bodyDetected)
    }

    func testValidAngle_bodyDetected() {
        feedAngle(170, frames: 1)
        XCTAssertTrue(detector.bodyDetected)
    }

    // MARK: - Phase Transitions (with debounce = 3 frames)

    func testHighAngle_transitionsToUp() {
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    func testLowAngle_transitionsToDown() {
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)
    }

    func testMidAngle_noTransition() {
        feedAngle(120, frames: 10)
        XCTAssertEqual(detector.phase, .unknown)
    }

    // MARK: - Debounce

    func testSingleFrame_noTransition() {
        feedAngle(170, frames: 1)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testTwoFrames_noTransition() {
        feedAngle(170, frames: 2)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testThreeFrames_transitionsToUp() {
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    // MARK: - Counting

    func testDownToUp_incrementsCount() {
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
        XCTAssertEqual(detector.count, 1)
    }

    func testUpToDown_doesNotIncrementCount() {
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)
        XCTAssertEqual(detector.count, 0)
    }

    func testFullPushupCycle_countsOne() {
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    func testTwoPushups() {
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 1
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 2
        XCTAssertEqual(detector.count, 2)
    }

    func testMidAngleBetweenPhases_doesNotCount() {
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(120, frames: 5)  // mid-range, no transition
        feedAngle(170, frames: 3)  // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    // MARK: - Reset

    func testReset_clearsEverything() {
        feedAngle(170, frames: 3)
        feedAngle(80, frames: 3)
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.count, 1)

        detector.reset()
        XCTAssertEqual(detector.count, 0)
        XCTAssertEqual(detector.phase, .unknown)
        XCTAssertFalse(detector.bodyDetected)
    }

    // MARK: - Helpers

    private func feedAngle(_ angle: Double, frames: Int) {
        for _ in 0..<frames {
            detector.processAngle(angle)
        }
    }
}

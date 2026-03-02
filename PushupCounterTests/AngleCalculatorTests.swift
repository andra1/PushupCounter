import XCTest
@testable import PushupCounter

final class AngleCalculatorTests: XCTestCase {

    func testStraightLine_returns180Degrees() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 0),
            b: CGPoint(x: 1, y: 0),
            c: CGPoint(x: 2, y: 0)
        )
        XCTAssertEqual(angle, 180.0, accuracy: 0.1)
    }

    func testRightAngle_returns90Degrees() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }

    func test45Degrees() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 45.0, accuracy: 0.1)
    }

    func test120Degrees() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: -1, y: sqrt(3.0))
        )
        XCTAssertEqual(angle, 120.0, accuracy: 0.1)
    }

    func testZeroDegrees_sameDirection() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 2, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 0.0, accuracy: 0.1)
    }

    func testDegenerateInput_zeroLengthVector_returnsZero() {
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 0.0, accuracy: 0.1)
    }
}

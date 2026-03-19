import XCTest
@testable import PushupCounter

final class RepAngleTests: XCTestCase {

    // MARK: - RepAngle Codable

    func testRepAngle_encodeDecode_roundTrips() throws {
        let angles = [
            RepAngle(minAngle: 85.0, maxAngle: 165.0),
            RepAngle(minAngle: 95.0, maxAngle: 150.0)
        ]
        let data = try JSONEncoder().encode(angles)
        let decoded = try JSONDecoder().decode([RepAngle].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].minAngle, 85.0)
        XCTAssertEqual(decoded[0].maxAngle, 165.0)
        XCTAssertEqual(decoded[1].minAngle, 95.0)
        XCTAssertEqual(decoded[1].maxAngle, 150.0)
    }

    // MARK: - RepAngle.hasFullRangeOfMotion

    func testHasFullROM_deepAndExtended_returnsTrue() {
        let rep = RepAngle(minAngle: 85.0, maxAngle: 165.0)
        XCTAssertTrue(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_notDeepEnough_returnsFalse() {
        let rep = RepAngle(minAngle: 95.0, maxAngle: 165.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_notExtendedEnough_returnsFalse() {
        let rep = RepAngle(minAngle: 85.0, maxAngle: 150.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_exactThresholds_returnsFalse() {
        let rep = RepAngle(minAngle: 90.0, maxAngle: 160.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    // MARK: - PushupSession.formScore

    func testFormScore_allGoodReps_returns100() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 3)
        let angles = [
            RepAngle(minAngle: 80.0, maxAngle: 170.0),
            RepAngle(minAngle: 85.0, maxAngle: 165.0),
            RepAngle(minAngle: 88.0, maxAngle: 162.0)
        ]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.formScore, 100.0)
    }

    func testFormScore_mixedReps_returnsCorrectPercentage() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 4)
        let angles = [
            RepAngle(minAngle: 80.0, maxAngle: 170.0),  // good
            RepAngle(minAngle: 95.0, maxAngle: 165.0),  // bad (not deep)
            RepAngle(minAngle: 85.0, maxAngle: 150.0),  // bad (not extended)
            RepAngle(minAngle: 88.0, maxAngle: 162.0)   // good
        ]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.formScore, 50.0)
    }

    func testFormScore_noAngleData_returnsNil() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 5)
        XCTAssertNil(session.formScore)
    }

    func testFormScore_emptyAngles_returnsNil() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 0)
        session.repAnglesData = try? JSONEncoder().encode([RepAngle]())
        XCTAssertNil(session.formScore)
    }

    // MARK: - PushupSession.repAngles

    func testRepAngles_nilData_returnsEmpty() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 0)
        XCTAssertTrue(session.repAngles.isEmpty)
    }

    func testRepAngles_validData_returnsDecoded() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 2)
        let angles = [RepAngle(minAngle: 80.0, maxAngle: 170.0)]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.repAngles.count, 1)
        XCTAssertEqual(session.repAngles[0].minAngle, 80.0)
    }
}

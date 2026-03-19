import XCTest
import SwiftData
@testable import PushupCounter

final class DailyRecordTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: DailyRecord.self, PushupSession.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func testDailyRecordTotalPushups_noSessions_returnsZero() {
        let record = DailyRecord(date: Date())
        context.insert(record)
        XCTAssertEqual(record.totalPushups, 0)
    }

    func testDailyRecordTotalPushups_multipleSessions_returnsSumOfCounts() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        let session1 = PushupSession(startTime: Date(), endTime: Date(), count: 15)
        session1.dailyRecord = record
        record.sessions.append(session1)

        let session2 = PushupSession(startTime: Date(), endTime: Date(), count: 20)
        session2.dailyRecord = record
        record.sessions.append(session2)

        context.insert(session1)
        context.insert(session2)

        XCTAssertEqual(record.totalPushups, 35)
    }

    // MARK: - Form Score

    func testFormScore_noSessions_returnsNil() {
        let record = DailyRecord(date: Date())
        context.insert(record)
        XCTAssertNil(record.formScore)
    }

    func testFormScore_sessionsWithoutAngleData_returnsNil() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        let session = PushupSession(startTime: Date(), endTime: Date(), count: 10)
        session.dailyRecord = record
        record.sessions.append(session)
        context.insert(session)

        XCTAssertNil(record.formScore)
    }

    func testFormScore_singleSession_returnsSessionScore() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        let session = PushupSession(startTime: Date(), endTime: Date(), count: 2)
        let angles = [
            RepAngle(minAngle: 80.0, maxAngle: 170.0),  // good
            RepAngle(minAngle: 95.0, maxAngle: 170.0)   // bad
        ]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        session.dailyRecord = record
        record.sessions.append(session)
        context.insert(session)

        XCTAssertEqual(record.formScore, 50.0)
    }

    func testFormScore_multipleSessions_weightsByRepCount() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        // Session 1: 1 rep, 100% form
        let s1 = PushupSession(startTime: Date(), endTime: Date(), count: 1)
        s1.repAnglesData = try? JSONEncoder().encode([RepAngle(minAngle: 80.0, maxAngle: 170.0)])
        s1.dailyRecord = record
        record.sessions.append(s1)
        context.insert(s1)

        // Session 2: 3 reps, 0% form
        let s2 = PushupSession(startTime: Date(), endTime: Date(), count: 3)
        s2.repAnglesData = try? JSONEncoder().encode([
            RepAngle(minAngle: 95.0, maxAngle: 170.0),
            RepAngle(minAngle: 95.0, maxAngle: 170.0),
            RepAngle(minAngle: 95.0, maxAngle: 170.0)
        ])
        s2.dailyRecord = record
        record.sessions.append(s2)
        context.insert(s2)

        // Weighted: (1 * 100 + 3 * 0) / (1 + 3) = 25.0
        XCTAssertEqual(record.formScore!, 25.0, accuracy: 0.1)
    }

    func testFormScore_mixOfLegacyAndNewSessions_ignoresLegacy() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        // Legacy session (no angle data)
        let legacy = PushupSession(startTime: Date(), endTime: Date(), count: 20)
        legacy.dailyRecord = record
        record.sessions.append(legacy)
        context.insert(legacy)

        // New session with angle data
        let s1 = PushupSession(startTime: Date(), endTime: Date(), count: 2)
        s1.repAnglesData = try? JSONEncoder().encode([
            RepAngle(minAngle: 80.0, maxAngle: 170.0),
            RepAngle(minAngle: 80.0, maxAngle: 170.0)
        ])
        s1.dailyRecord = record
        record.sessions.append(s1)
        context.insert(s1)

        // Only considers the new session: 100%
        XCTAssertEqual(record.formScore, 100.0)
    }
}

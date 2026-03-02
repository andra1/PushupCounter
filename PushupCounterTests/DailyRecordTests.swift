import XCTest
import SwiftData
@testable import PushupCounter

final class DailyRecordTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: UserSettings.self, DailyRecord.self, PushupSession.self,
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

    func testUserSettingsDefaults() {
        let settings = UserSettings()
        context.insert(settings)
        XCTAssertEqual(settings.dailyGoal, 30)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
}

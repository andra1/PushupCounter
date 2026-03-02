import Foundation
import SwiftData

@Model
final class DailyRecord {
    var date: Date
    var goalMet: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \PushupSession.dailyRecord)
    var sessions: [PushupSession] = []

    var totalPushups: Int {
        sessions.reduce(0) { $0 + $1.count }
    }

    init(date: Date, goalMet: Bool = false) {
        self.date = date
        self.goalMet = goalMet
    }
}

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

    var formScore: Double? {
        let scored = sessions.filter { $0.formScore != nil }
        guard !scored.isEmpty else { return nil }
        let totalReps = scored.reduce(0) { $0 + $1.repAngles.count }
        guard totalReps > 0 else { return nil }
        let weightedSum = scored.reduce(0.0) { $0 + ($1.formScore! * Double($1.repAngles.count)) }
        return weightedSum / Double(totalReps)
    }

    init(date: Date, goalMet: Bool = false) {
        self.date = date
        self.goalMet = goalMet
    }
}

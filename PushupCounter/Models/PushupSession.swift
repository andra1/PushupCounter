import Foundation
import SwiftData

@Model
final class PushupSession {
    var startTime: Date
    var endTime: Date
    var count: Int
    var dailyRecord: DailyRecord?
    @Attribute var repAnglesData: Data?

    var repAngles: [RepAngle] {
        guard let data = repAnglesData else { return [] }
        return (try? JSONDecoder().decode([RepAngle].self, from: data)) ?? []
    }

    var formScore: Double? {
        let angles = repAngles
        guard !angles.isEmpty else { return nil }
        let goodReps = angles.filter { $0.hasFullRangeOfMotion }.count
        return Double(goodReps) / Double(angles.count) * 100.0
    }

    init(startTime: Date, endTime: Date, count: Int) {
        self.startTime = startTime
        self.endTime = endTime
        self.count = count
    }
}

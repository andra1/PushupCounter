import Foundation
import SwiftData

@Model
final class PushupSession {
    var startTime: Date
    var endTime: Date
    var count: Int
    var dailyRecord: DailyRecord?

    init(startTime: Date, endTime: Date, count: Int) {
        self.startTime = startTime
        self.endTime = endTime
        self.count = count
    }
}

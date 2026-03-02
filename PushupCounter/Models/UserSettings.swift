import Foundation
import SwiftData

@Model
final class UserSettings {
    var dailyGoal: Int = 30
    var selectedAppsData: Data?
    var soundEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false

    init(dailyGoal: Int = 30, soundEnabled: Bool = true) {
        self.dailyGoal = dailyGoal
        self.soundEnabled = soundEnabled
    }
}

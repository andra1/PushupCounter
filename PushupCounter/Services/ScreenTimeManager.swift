import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import Observation

extension DeviceActivityName {
    static let daily = Self("com.pushupcounter.daily")
}

@Observable
final class ScreenTimeManager {
    private(set) var isAuthorized = false
    var selection = FamilyActivitySelection()

    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()

    static let sharedDefaults = UserDefaults(suiteName: "group.com.pushupcounter.shared")

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    func saveSelection() {
        let data = try? PropertyListEncoder().encode(selection)
        Self.sharedDefaults?.set(data, forKey: "selectedApps")
        applyShields()
        scheduleDailyMonitoring()
    }

    func loadSelection() {
        guard let data = Self.sharedDefaults?.data(forKey: "selectedApps"),
              let saved = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        selection = saved
    }

    func applyShields() {
        let tokens = selection.applicationTokens
        store.shield.applications = tokens.isEmpty ? nil : tokens
    }

    func removeShields() {
        store.shield.applications = nil
    }

    func scheduleDailyMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(.daily, during: schedule)
        } catch {
            print("Failed to start monitoring: \(error)")
        }
    }

    var hasSelectedApps: Bool {
        !selection.applicationTokens.isEmpty
    }
}

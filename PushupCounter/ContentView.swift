import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    @State private var screenTimeManager = ScreenTimeManager()
    @State private var pushupDetector = PushupDetector()

    private var settings: UserSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = UserSettings()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        if !settings.hasCompletedOnboarding {
            OnboardingView(settings: settings, screenTimeManager: screenTimeManager)
                .environment(screenTimeManager)
                .environment(pushupDetector)
        } else {
            TabView {
                TodayView(settings: settings)
                    .tabItem {
                        Label("Today", systemImage: "figure.strengthtraining.traditional")
                    }
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "calendar")
                    }
                SettingsView(settings: settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .environment(screenTimeManager)
            .environment(pushupDetector)
            .onAppear {
                screenTimeManager.loadSelection()
            }
        }
    }
}

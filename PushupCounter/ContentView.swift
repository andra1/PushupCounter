import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    @State private var screenTimeManager = ScreenTimeManager()
    @State private var pushupDetector = PushupDetector()
    @State private var settings: UserSettings?

    var body: some View {
        Group {
            if let settings {
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
            } else {
                ProgressView()
            }
        }
        .onAppear {
            ensureSettings()
        }
        .onChange(of: settingsList) {
            ensureSettings()
        }
    }

    private func ensureSettings() {
        if let existing = settingsList.first {
            settings = existing
        } else if settings == nil {
            let new = UserSettings()
            modelContext.insert(new)
            settings = new
        }
    }
}

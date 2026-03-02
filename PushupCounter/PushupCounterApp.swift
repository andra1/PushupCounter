import SwiftUI
import SwiftData

@main
struct PushupCounterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [UserSettings.self, DailyRecord.self, PushupSession.self])
    }
}

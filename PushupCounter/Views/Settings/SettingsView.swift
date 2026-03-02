import SwiftUI
import FamilyControls
import SwiftData

struct SettingsView: View {
    @Bindable var settings: UserSettings
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext
    @State private var isPickerPresented = false
    @State private var showResetConfirmation = false

    var body: some View {
        @Bindable var manager = screenTimeManager

        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper("\(settings.dailyGoal) pushups", value: $settings.dailyGoal, in: 1...200)
                }

                Section("Blocked Apps") {
                    Button("Change Blocked Apps") {
                        isPickerPresented = true
                    }
                    .familyActivityPicker(
                        isPresented: $isPickerPresented,
                        selection: $manager.selection
                    )
                    .onChange(of: screenTimeManager.selection) {
                        screenTimeManager.saveSelection()
                    }
                }

                Section("Sound") {
                    Toggle("Rep Completion Sound", isOn: $settings.soundEnabled)
                }

                Section("Stats") {
                    let records = fetchAllRecords()
                    LabeledContent("Total Pushups (All Time)", value: "\(records.reduce(0) { $0 + $1.totalPushups })")
                    LabeledContent("Days Completed", value: "\(records.filter(\.goalMet).count)")
                    LabeledContent("Total Sessions", value: "\(records.reduce(0) { $0 + $1.sessions.count })")
                }

                Section {
                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset all data?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all pushup history, reset your goal, and remove app blocking. This cannot be undone.")
            }
        }
    }

    private func fetchAllRecords() -> [DailyRecord] {
        let descriptor = FetchDescriptor<DailyRecord>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resetAllData() {
        let records = fetchAllRecords()
        for record in records {
            modelContext.delete(record)
        }
        settings.dailyGoal = 30
        settings.soundEnabled = true
        settings.hasCompletedOnboarding = false
        settings.selectedAppsData = nil
        screenTimeManager.removeShields()
        try? modelContext.save()
    }
}

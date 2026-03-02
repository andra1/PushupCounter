import SwiftUI

struct PushupSessionView: View {
    let settings: UserSettings
    let dailyRecord: DailyRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Session — TODO")
        Button("Done") { dismiss() }
    }
}

import SwiftUI

struct DayDetailView: View {
    let record: DailyRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Date", value: record.date, format: .dateTime.month().day().year())
                    LabeledContent("Total Pushups", value: "\(record.totalPushups)")
                    LabeledContent("Goal Met", value: record.goalMet ? "Yes" : "No")
                    LabeledContent("Sessions", value: "\(record.sessions.count)")
                }

                Section("Sessions") {
                    ForEach(record.sessions.sorted(by: { $0.startTime < $1.startTime })) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.startTime, style: .time)
                                    .font(.headline)
                                Text("\(session.count) pushups")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let duration = session.endTime.timeIntervalSince(session.startTime)
                            Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds])))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Day Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

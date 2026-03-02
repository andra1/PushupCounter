import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DailyRecord.date, order: .reverse) private var records: [DailyRecord]
    @State private var selectedRecord: DailyRecord?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "calendar.badge.clock",
                        description: Text("Complete your first pushup session to start tracking progress.")
                    )
                } else {
                    List(records) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            HStack {
                                Circle()
                                    .fill(record.goalMet ? .green : .red)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(record.date, style: .date)
                                        .font(.headline)
                                    Text("\(record.totalPushups) pushups in \(record.sessions.count) session(s)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if record.goalMet {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedRecord) { record in
                DayDetailView(record: record)
            }
        }
    }
}

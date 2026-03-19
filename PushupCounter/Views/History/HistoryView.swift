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
                            CompactCardView(record: record)
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

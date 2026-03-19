import SwiftUI
import SwiftData

struct TodayView: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Query private var allRecords: [DailyRecord]
    @State private var showingSession = false
    @State private var todayRecord: DailyRecord?

    private func ensureTodayRecord() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        if let existing = allRecords.first(where: { calendar.isDate($0.date, inSameDayAs: startOfDay) }) {
            todayRecord = existing
        } else if todayRecord == nil {
            let record = DailyRecord(date: startOfDay)
            modelContext.insert(record)
            todayRecord = record
        }
    }

    private var goalMet: Bool {
        guard let todayRecord else { return false }
        return todayRecord.totalPushups >= settings.dailyGoal
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let sorted = allRecords
            .filter { $0.goalMet }
            .sorted { $0.date > $1.date }

        var streak = 0
        var expectedDate = calendar.startOfDay(for: Date())

        // If today's goal is met, count today
        if goalMet {
            streak = 1
            expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
        }

        for record in sorted {
            let recordDate = calendar.startOfDay(for: record.date)
            if calendar.isDate(recordDate, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
            } else if recordDate < expectedDate {
                break
            }
        }
        return streak
    }

    var body: some View {
        NavigationStack {
            if let todayRecord {
                ScrollView {
                    VStack(spacing: 24) {
                        if todayRecord.totalPushups > 0 {
                            DailyCardView(record: todayRecord)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        } else {
                            VStack(spacing: 12) {
                                Text("0")
                                    .font(.system(size: 72, weight: .bold, design: .rounded))
                                Text("pushups today")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 60)
                        }

                        Spacer(minLength: 40)

                        Button {
                            showingSession = true
                        } label: {
                            Label("Start Pushups", systemImage: "play.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
                .fullScreenCover(isPresented: $showingSession) {
                    PushupSessionView(settings: settings, dailyRecord: todayRecord)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Today")
        .onAppear {
            ensureTodayRecord()
        }
        .onChange(of: allRecords) {
            ensureTodayRecord()
        }
    }
}

import SwiftUI
import SwiftData

struct TodayView: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Query private var allRecords: [DailyRecord]
    @State private var showingSession = false

    private var todayRecord: DailyRecord {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        if let existing = allRecords.first(where: { calendar.isDate($0.date, inSameDayAs: startOfDay) }) {
            return existing
        }
        let record = DailyRecord(date: startOfDay)
        modelContext.insert(record)
        return record
    }

    private var goalMet: Bool {
        todayRecord.totalPushups >= settings.dailyGoal
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
            VStack(spacing: 32) {
                Spacer()

                ProgressRingView(
                    progress: settings.dailyGoal > 0
                        ? Double(todayRecord.totalPushups) / Double(settings.dailyGoal)
                        : 0,
                    current: todayRecord.totalPushups,
                    goal: settings.dailyGoal
                )
                .frame(width: 220, height: 220)

                HStack(spacing: 8) {
                    Image(systemName: goalMet ? "lock.open.fill" : "lock.fill")
                    Text(goalMet ? "Unlocked" : "Locked")
                        .font(.title2.bold())
                }
                .foregroundStyle(goalMet ? .green : .red)

                if currentStreak > 0 {
                    Label("\(currentStreak) day streak", systemImage: "flame.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    showingSession = true
                } label: {
                    Label("Start Pushups", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(goalMet ? .green : .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showingSession) {
                PushupSessionView(settings: settings, dailyRecord: todayRecord)
            }
        }
    }
}

import SwiftUI

struct DailyCardView: View {
    let record: DailyRecord

    private var totalTime: TimeInterval {
        record.sessions.reduce(0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    }

    private var formattedTime: String {
        let duration = Duration.seconds(totalTime)
        return duration.formatted(.units(allowed: [.minutes, .seconds]))
    }

    private var sortedSessions: [PushupSession] {
        record.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Text(record.date.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("PUSHUP COUNTER")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
            }
            .padding(.bottom, 24)

            // Form quality ring
            if let score = record.formScore {
                FormQualityRingView(score: score, size: 140)
                    .padding(.bottom, 28)
            }

            // Stats row
            HStack {
                statColumn(value: "\(record.totalPushups)", label: "PUSHUPS")
                Spacer()
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.2))
                Spacer()
                statColumn(value: "\(record.sessions.count)", label: "SETS")
                Spacer()
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.2))
                Spacer()
                statColumn(value: formattedTime, label: "TIME")
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }

            // Set chips
            if !sortedSessions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        setChip(index: index + 1, session: session)
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
    }

    private func setChip(index: Int, session: PushupSession) -> some View {
        VStack(spacing: 4) {
            Text("\(session.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chipColor(for: session))
            Text("SET \(index)")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func chipColor(for session: PushupSession) -> Color {
        guard let score = session.formScore else { return .white }
        if score >= 70 { return .green }
        if score >= 40 { return .yellow }
        return .red
    }
}

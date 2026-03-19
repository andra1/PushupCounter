import SwiftUI

struct CompactCardView: View {
    let record: DailyRecord

    var body: some View {
        HStack(spacing: 16) {
            // Mini form ring
            if let score = record.formScore {
                FormQualityRingView(score: score, size: 48, animated: false)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.date, style: .date)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label("\(record.totalPushups)", systemImage: "figure.strengthtraining.traditional")
                    Label("\(record.sessions.count)", systemImage: "number")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

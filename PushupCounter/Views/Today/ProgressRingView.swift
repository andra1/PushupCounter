import SwiftUI

struct ProgressRingView: View {
    let progress: Double  // 0.0 to 1.0
    let current: Int
    let goal: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    progress >= 1.0 ? Color.green : Color.blue,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 4) {
                Text("\(current)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("of \(goal)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

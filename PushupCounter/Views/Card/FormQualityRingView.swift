import SwiftUI

struct FormQualityRingView: View {
    let score: Double  // 0-100
    let size: CGFloat
    var animated: Bool = true

    @State private var animatedProgress: Double = 0

    private var progress: Double { score / 100.0 }

    private var ringColor: LinearGradient {
        if score >= 70 {
            return LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if score >= 40 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: size * 0.057)

            // Progress ring
            Circle()
                .trim(from: 0, to: animated ? animatedProgress : progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: size * 0.057, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 2) {
                Text("\(Int(animated ? animatedProgress * 100 : score))%")
                    .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("FORM")
                    .font(.system(size: size * 0.08))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = progress
            }
        }
    }
}

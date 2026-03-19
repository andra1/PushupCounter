import SwiftUI
import AVFoundation
import SwiftData

struct PushupSessionView: View {
    @Bindable var settings: UserSettings
    @Bindable var dailyRecord: DailyRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(PushupDetector.self) private var pushupDetector

    @State private var cameraManager: CameraManager?
    @State private var sessionStartTime = Date()
    @State private var showCelebration = false

    private var totalToday: Int {
        dailyRecord.totalPushups + pushupDetector.count
    }

    private var goalReached: Bool {
        totalToday >= settings.dailyGoal
    }

    var body: some View {
        ZStack {
            // Camera preview
            if let cameraManager {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Overlay UI
            VStack {
                // Top: pushup count
                Text("\(pushupDetector.count)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(.top, 60)

                // Phase indicator
                HStack {
                    Circle()
                        .fill(pushupDetector.bodyDetected ? .green : .red)
                        .frame(width: 12, height: 12)
                    Text(pushupDetector.bodyDetected
                         ? (pushupDetector.phase == .down ? "DOWN" : pushupDetector.phase == .up ? "UP" : "READY")
                         : "No body detected")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                // Progress toward daily goal
                VStack(spacing: 8) {
                    ProgressView(value: Double(totalToday), total: Double(settings.dailyGoal))
                        .tint(goalReached ? .green : .blue)
                        .scaleEffect(y: 2)
                        .padding(.horizontal, 40)

                    Text("\(totalToday) / \(settings.dailyGoal) today")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

                // Done button
                Button {
                    endSession()
                } label: {
                    Text("Done")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // Celebration overlay
            if showCelebration {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                    Text("Goal Reached!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Your apps are now unlocked")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.7))
                .onTapGesture {
                    endSession()
                }
            }
        }
        .onAppear {
            sessionStartTime = Date()
            pushupDetector.reset()
            let manager = CameraManager(pushupDetector: pushupDetector)
            cameraManager = manager
            Task {
                await manager.requestPermission()
                manager.setupSession()
                manager.startSession()
            }
        }
        .onDisappear {
            cameraManager?.stopSession()
        }
        .onChange(of: goalReached) { _, reached in
            if reached && !showCelebration {
                showCelebration = true
                if settings.soundEnabled {
                    AudioServicesPlaySystemSound(1025) // completion sound
                }
            }
        }
        .onChange(of: pushupDetector.count) { oldCount, newCount in
            if newCount > oldCount && settings.soundEnabled && !goalReached {
                AudioServicesPlaySystemSound(1057) // tock sound for each rep
            }
        }
        .statusBarHidden()
    }

    private func endSession() {
        cameraManager?.stopSession()
        let count = pushupDetector.count
        guard count > 0 else {
            dismiss()
            return
        }

        let session = PushupSession(startTime: sessionStartTime, endTime: Date(), count: count)
        session.repAnglesData = try? JSONEncoder().encode(pushupDetector.completedRepAngles)
        session.dailyRecord = dailyRecord
        dailyRecord.sessions.append(session)
        modelContext.insert(session)

        if dailyRecord.totalPushups >= settings.dailyGoal {
            dailyRecord.goalMet = true
            screenTimeManager.removeShields()
        }

        try? modelContext.save()
        dismiss()
    }
}

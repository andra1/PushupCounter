import SwiftUI

struct GoalStepView: View {
    @Bindable var settings: UserSettings
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Set Your Daily Goal")
                .font(.largeTitle.bold())

            Text("How many pushups per day?")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("Daily Goal", selection: $settings.dailyGoal) {
                ForEach([5, 10, 15, 20, 25, 30, 40, 50, 75, 100], id: \.self) { count in
                    Text("\(count) pushups").tag(count)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)

            Text("\(settings.dailyGoal) pushups")
                .font(.title.bold())
                .foregroundStyle(.blue)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

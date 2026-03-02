import SwiftUI
import FamilyControls

struct PermissionsStepView: View {
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    let onComplete: () -> Void
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var manager = screenTimeManager

        VStack(spacing: 24) {
            Spacer()

            Text("Choose Apps to Lock")
                .font(.largeTitle.bold())

            Text("Select the apps you want blocked until you complete your daily pushups.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !screenTimeManager.isAuthorized {
                Button("Grant Screen Time Access") {
                    Task {
                        await screenTimeManager.requestAuthorization()
                    }
                }
                .font(.headline)
                .padding()
                .background(.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button("Select Apps to Block") {
                    isPickerPresented = true
                }
                .font(.headline)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .familyActivityPicker(
                    isPresented: $isPickerPresented,
                    selection: $manager.selection
                )

                if screenTimeManager.hasSelectedApps {
                    Text("Apps selected!")
                        .foregroundStyle(.green)
                        .font(.headline)
                }
            }

            Spacer()

            Button(action: {
                screenTimeManager.saveSelection()
                onComplete()
            }) {
                Text("Finish Setup")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(screenTimeManager.hasSelectedApps ? .blue : .gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!screenTimeManager.hasSelectedApps)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

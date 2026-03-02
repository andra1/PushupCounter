import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: UserSettings
    let screenTimeManager: ScreenTimeManager
    @State private var currentStep = 0

    var body: some View {
        TabView(selection: $currentStep) {
            WelcomeStepView {
                withAnimation { currentStep = 1 }
            }
            .tag(0)

            GoalStepView(settings: settings) {
                withAnimation { currentStep = 2 }
            }
            .tag(1)

            PermissionsStepView {
                settings.hasCompletedOnboarding = true
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }
}

import SwiftUI

struct RootView: View {
    let appModel: AppModel

    var body: some View {
        Group {
            if !appModel.hasLoaded {
                ZStack {
                    AppTheme.canvas.ignoresSafeArea()
                    LoadingStateView(title: "Preparing OpenCode Client…")
                }
            } else if appModel.profiles.isEmpty {
                OnboardingView(appModel: appModel)
            } else {
                AppShellView(appModel: appModel)
            }
        }
        .task {
            if !appModel.hasLoaded {
                await appModel.load()
            }
        }
    }
}

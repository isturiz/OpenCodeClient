import SwiftUI

struct OnboardingView: View {
    let appModel: AppModel
    @State private var showsServerEditor = false

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                AppMark(size: 86)

                VStack(spacing: 12) {
                    Text("Your code, within reach.")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(
                        "Connect to an OpenCode server to review projects, follow agent work, and steer sessions by text or voice."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                }

                VStack(alignment: .leading, spacing: 14) {
                    onboardingRow(icon: "folder", title: "Browse projects and sessions")
                    onboardingRow(icon: "bolt.horizontal", title: "Follow responses in real time")
                    onboardingRow(icon: "waveform", title: "Dictate through FluidVoice")
                }

                Spacer()

                Button {
                    showsServerEditor = true
                } label: {
                    Text("Add OpenCode Server")
                        .frame(maxWidth: 420)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding-add-server")
            }
            .padding(32)
        }
        .sheet(isPresented: $showsServerEditor) {
            ServerEditorView(appModel: appModel, makeActive: true)
        }
    }

    private func onboardingRow(icon: String, title: LocalizedStringKey) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.signal)
                .frame(width: 28)
        }
        .font(.callout.weight(.medium))
    }
}

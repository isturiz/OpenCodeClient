import SwiftUI

struct AppShellView: View {
    let appModel: AppModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var projectsModel = ProjectsViewModel()
    @State private var compactPath: [SessionRoute] = []
    @State private var selectedRoute: SessionRoute?
    @State private var showsSettings = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(appModel: appModel)
        }
        .task(id: appModel.activeProfileID) {
            compactPath.removeAll()
            selectedRoute = nil
            guard let profile = appModel.activeProfile else { return }
            do {
                let client = try await appModel.client(for: profile)
                await projectsModel.connect(profile: profile, client: client)
            } catch {
                projectsModel.fail(error)
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            ProjectsView(
                appModel: appModel,
                model: projectsModel,
                onSelect: { compactPath.append($0) },
                onOpenSettings: { showsSettings = true }
            )
            .navigationDestination(for: SessionRoute.self) { route in
                ChatContainerView(
                    appModel: appModel,
                    route: route,
                    onOpenSettings: { showsSettings = true }
                )
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ProjectsView(
                appModel: appModel,
                model: projectsModel,
                onSelect: { selectedRoute = $0 },
                onOpenSettings: { showsSettings = true }
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
        } detail: {
            if let selectedRoute {
                NavigationStack {
                    ChatContainerView(
                        appModel: appModel,
                        route: selectedRoute,
                        onOpenSettings: { showsSettings = true }
                    )
                }
                .id(selectedRoute.id)
            } else {
                ContentUnavailableView {
                    Label("Select a session", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Choose a project session to review its conversation.")
                }
                .background(AppTheme.canvas)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ChatContainerView: View {
    let appModel: AppModel
    let route: SessionRoute
    let onOpenSettings: () -> Void

    @State private var model = ChatViewModel()

    var body: some View {
        ChatView(model: model, onOpenSettings: onOpenSettings)
            .task(id: route.id) {
                guard let profile = appModel.profiles.first(where: { $0.id == route.profileID }) else {
                    model.presentedError = String(
                        localized: "The server profile for this session no longer exists.")
                    return
                }
                do {
                    let client = try await appModel.client(for: profile)
                    let voiceClient = try? await appModel.fluidVoiceClient()
                    await model.configure(
                        route: route,
                        client: client,
                        voiceClient: voiceClient,
                        usesVoicePostProcessing: appModel.voiceConfiguration.usesPostProcessing
                    )
                } catch {
                    model.presentedError = error.localizedDescription
                }
            }
    }
}

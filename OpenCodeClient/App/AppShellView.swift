import SwiftUI

struct AppShellView: View {
    let appModel: AppModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var projectsModel = ProjectsViewModel()
    @State private var compactPath: [ConversationRoute] = []
    @State private var selectedRoute: ConversationRoute?
    @State private var conversationModels: [UUID: ChatViewModel] = [:]
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
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            if sizeClass == .regular {
                selectedRoute = compactPath.last
            } else {
                compactPath = selectedRoute.map { [$0] } ?? []
            }
        }
        .onChange(of: compactPath) { _, path in
            if horizontalSizeClass != .regular {
                selectedRoute = path.last
            }
            cleanConversationModels()
        }
        .onChange(of: selectedRoute) { _, _ in cleanConversationModels() }
        .task(id: appModel.serverConfigurationRevision) {
            let revision = appModel.serverConfigurationRevision
            projectsModel.organization = appModel.sessionOrganization
            guard let profile = appModel.activeProfile else { return }
            discardConversations(notMatching: profile.id)
            projectsModel.prepareForConnection(to: profile)
            do {
                let client = try await appModel.client(for: profile)
                try Task.checkCancellation()
                guard
                    appModel.serverConfigurationRevision == revision,
                    appModel.activeProfileID == profile.id
                else { return }
                await projectsModel.connect(profile: profile, client: client)
            } catch is CancellationError {
                return
            } catch {
                guard
                    appModel.serverConfigurationRevision == revision,
                    appModel.activeProfileID == profile.id
                else { return }
                projectsModel.fail(error)
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            ProjectsView(
                appModel: appModel,
                model: projectsModel,
                onSelect: { selectCompact($0) },
                onNewChat: { selectCompact(newChatRoute(project: $0)) },
                onOpenSettings: { showsSettings = true }
            )
            .navigationDestination(for: ConversationRoute.self) { route in
                ChatContainerView(
                    appModel: appModel,
                    model: conversationModel(for: route),
                    conversationRoute: route,
                    onSessionRouteChanged: { promote(route.id, to: $0) },
                    onNewChat: { sessionRoute in
                        selectCompact(
                            newChatRoute(
                                profileID: sessionRoute.profileID,
                                project: sessionRoute.project
                            )
                        )
                    },
                    onTogglePin: { togglePin($0) }
                )
                .id(route.id)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ProjectsView(
                appModel: appModel,
                model: projectsModel,
                onSelect: { selectRegular($0) },
                onNewChat: { selectRegular(newChatRoute(project: $0)) },
                onOpenSettings: { showsSettings = true }
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
        } detail: {
            if let selectedRoute {
                NavigationStack {
                    ChatContainerView(
                        appModel: appModel,
                        model: conversationModel(for: selectedRoute),
                        conversationRoute: selectedRoute,
                        onSessionRouteChanged: { promote(selectedRoute.id, to: $0) },
                        onNewChat: { sessionRoute in
                            selectRegular(
                                newChatRoute(
                                    profileID: sessionRoute.profileID,
                                    project: sessionRoute.project
                                )
                            )
                        },
                        onTogglePin: { togglePin($0) }
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

    private func newChatRoute(
        profileID: UUID? = nil,
        project: OpenCodeProject?
    ) -> ConversationRoute {
        ConversationRoute(
            destination: .newChat(
                NewChatRoute(profileID: profileID ?? appModel.activeProfileID, project: project)
            )
        )
    }

    private func selectCompact(_ route: ConversationRoute) {
        registerModel(for: route)
        compactPath.append(route)
    }

    private func selectRegular(_ route: ConversationRoute) {
        registerModel(for: route)
        selectedRoute = route
    }

    private func registerModel(for route: ConversationRoute) {
        if conversationModels[route.id] == nil {
            conversationModels[route.id] = ChatViewModel()
        }
    }

    private func conversationModel(for route: ConversationRoute) -> ChatViewModel {
        conversationModels[route.id] ?? ChatViewModel()
    }

    private func cleanConversationModels() {
        let retainedIDs = Set(compactPath.map(\.id) + [selectedRoute?.id].compactMap { $0 })
        conversationModels = conversationModels.filter { retainedIDs.contains($0.key) }
    }

    private func promote(_ conversationID: UUID, to sessionRoute: SessionRoute) {
        var conversationStillExists = false
        var didMaterialize = false
        if let index = compactPath.firstIndex(where: { $0.id == conversationID }) {
            if case .newChat = compactPath[index].destination {
                didMaterialize = true
            }
            compactPath[index].destination = .session(sessionRoute)
            conversationStillExists = true
        }
        if selectedRoute?.id == conversationID {
            if let selectedRoute, case .newChat = selectedRoute.destination {
                didMaterialize = true
            }
            selectedRoute?.destination = .session(sessionRoute)
            conversationStillExists = true
        }

        guard conversationStillExists else { return }
        if appModel.activeProfileID == sessionRoute.profileID {
            projectsModel.upsertSession(sessionRoute)
        }
        guard didMaterialize else { return }

        Task {
            if appModel.activeProfileID != sessionRoute.profileID {
                await appModel.activate(profileID: sessionRoute.profileID)
            } else {
                await projectsModel.refresh()
            }
        }
    }

    private func discardConversations(notMatching profileID: UUID) {
        compactPath.removeAll { route in
            guard let routeProfileID = route.profileID else { return false }
            return routeProfileID != profileID
        }
        if let routeProfileID = selectedRoute?.profileID, routeProfileID != profileID {
            selectedRoute = nil
        }
        cleanConversationModels()
    }

    private func togglePin(_ route: SessionRoute) {
        Task {
            await appModel.togglePinnedSession(
                profileID: route.profileID,
                sessionID: route.session.id
            )
            projectsModel.setPinnedSessions(
                appModel.pinnedSessions,
                profileID: appModel.activeProfileID
            )
        }
    }
}

private struct ChatContainerView: View {
    let appModel: AppModel
    let model: ChatViewModel
    let conversationRoute: ConversationRoute
    let onSessionRouteChanged: (SessionRoute) -> Void
    let onNewChat: (SessionRoute) -> Void
    let onTogglePin: (SessionRoute) -> Void

    @State private var reviewClient: (any OpenCodeClientProtocol)?
    @State private var showsChanges = false
    @State private var showsFiles = false

    var body: some View {
        ChatView(
            model: model,
            serverName: serverName,
            isPinned: model.route.map {
                appModel.isSessionPinned(profileID: $0.profileID, sessionID: $0.session.id)
            } ?? false,
            onNewChat: {
                guard let route = model.route else { return }
                onNewChat(route)
            },
            onTogglePin: {
                guard let route = model.route else { return }
                onTogglePin(route)
            },
            onOpenChanges: { showsChanges = true },
            onOpenFiles: { showsFiles = true }
        )
        .navigationDestination(isPresented: $showsChanges) {
            if let route = model.route, let reviewClient {
                ChangesView(
                    sessionID: route.session.id,
                    directory: route.session.directory,
                    client: reviewClient
                )
            } else {
                LoadingStateView(title: "Loading changes…")
            }
        }
        .navigationDestination(isPresented: $showsFiles) {
            if let route = model.route, let reviewClient {
                FilesView(directory: route.session.directory, client: reviewClient)
            } else {
                LoadingStateView(title: "Loading files…")
            }
        }
        .task(id: appModel.serverConfigurationRevision) {
            let voiceClient = try? await appModel.activeVoiceClient()
            let usesPostProcessing = appModel.activeVoiceProfile?.usesPostProcessing ?? false

            if let route = model.route {
                guard let profile = appModel.profile(withID: route.profileID) else {
                    model.presentedError = String(
                        localized: "The server profile for this session no longer exists.")
                    return
                }
                do {
                    let client = try await appModel.client(for: profile)
                    reviewClient = client
                    await model.reconfigureClient(client)
                } catch {
                    model.presentedError = error.localizedDescription
                }
                return
            }

            if model.phase != .idle {
                await model.refreshDraftConfiguration(appModel.profiles)
                return
            }

            switch conversationRoute.destination {
            case let .session(route):
                guard let profile = appModel.profile(withID: route.profileID) else {
                    model.presentedError = String(
                        localized: "The server profile for this session no longer exists.")
                    return
                }
                do {
                    let client = try await appModel.client(for: profile)
                    reviewClient = client
                    await model.configure(
                        route: route,
                        client: client,
                        voiceClient: voiceClient,
                        usesVoicePostProcessing: usesPostProcessing,
                        sessionRouteChanged: onSessionRouteChanged
                    )
                } catch {
                    model.presentedError = error.localizedDescription
                }

            case let .newChat(route):
                await model.configureNewChat(
                    profiles: appModel.profiles,
                    initialProfileID: route.profileID,
                    initialProject: route.project,
                    clientProvider: { profile in
                        try await appModel.client(for: profile)
                    },
                    voiceClient: voiceClient,
                    usesVoicePostProcessing: usesPostProcessing,
                    sessionRouteChanged: onSessionRouteChanged
                )
            }
        }
        .task(id: appModel.voiceConfigurationRevision) {
            let voiceClient = try? await appModel.activeVoiceClient()
            model.configureVoice(
                client: voiceClient,
                usesPostProcessing: appModel.activeVoiceProfile?.usesPostProcessing ?? false
            )
        }
        .task(id: model.route?.id) {
            guard let route = model.route,
                let profile = appModel.profile(withID: route.profileID)
            else { return }
            reviewClient = try? await appModel.client(for: profile)
        }
    }

    private var serverName: String? {
        if let selectedProfile = model.selectedProfile {
            return selectedProfile.name
        }
        return appModel.profile(withID: model.route?.profileID ?? conversationRoute.profileID)?.name
    }
}

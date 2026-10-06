import SwiftUI

struct ChatView: View {
    let model: ChatViewModel
    let serverName: String?
    let isPinned: Bool
    let onNewChat: () -> Void
    let onTogglePin: () -> Void
    let onOpenChanges: () -> Void
    let onOpenFiles: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isNearBottom = true
    @State private var shouldFollowLatest = true
    @State private var isUserInteracting = false
    @State private var hasPerformedInitialScroll = false
    @State private var jumpToLatestRequest = 0
    @State private var showsRename = false
    @State private var renameTitle = ""

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                LoadingStateView(title: "Loading conversation…")
            case .loading where model.messages.isEmpty:
                LoadingStateView(title: "Loading conversation…")
            case let .failed(message) where model.messages.isEmpty:
                ErrorStateView(title: "Couldn’t Load Conversation", message: message) {
                    Task { await model.load() }
                }
            default:
                transcript
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle(model.route?.session.title ?? String(localized: "New Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if !isNearBottom && !model.messages.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            shouldFollowLatest = true
                            jumpToLatestRequest &+= 1
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(
                                    width: AppTheme.minimumHitTarget,
                                    height: AppTheme.minimumHitTarget
                                )
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Jump to Latest")
                        .accessibilityIdentifier("jump-to-latest")
                        Spacer()
                    }
                }
                if model.isNewChat {
                    targetSelectors
                }
                ChatComposerView(model: model)
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.presentedError ?? "")
        }
        .alert("Rename Conversation", isPresented: $showsRename) {
            TextField("Title", text: $renameTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { await model.rename(to: renameTitle) }
            }
            .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for this conversation.")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.resume() }
            case .background:
                model.suspend()
            default:
                break
            }
        }
        .onDisappear { model.suspend() }
    }

    private var targetSelectors: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    serverSelector
                    projectSelector
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    serverSelector
                    projectSelector
                }
            }

            if let targetError = model.targetError {
                Text(targetError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, AppTheme.compactPadding)
    }

    private var serverSelector: some View {
        Menu {
            ForEach(model.availableProfiles) { profile in
                Button {
                    Task { await model.selectProfile(id: profile.id) }
                } label: {
                    if profile.id == model.selectedProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            Label(
                model.selectedProfile?.name ?? String(localized: "Server"),
                systemImage: "server.rack"
            )
            .lineLimit(1)
        }
        .buttonStyle(.glass)
        .disabled(!model.canChangeTarget || model.availableProfiles.isEmpty)
        .accessibilityLabel("Choose server")
        .accessibilityValue(model.selectedProfile?.name ?? String(localized: "None"))
        .accessibilityIdentifier("new-chat-server")
    }

    private var projectSelector: some View {
        Menu {
            ForEach(model.availableProjects) { project in
                Button {
                    Task { await model.selectProject(id: project.id) }
                } label: {
                    if project.id == model.selectedProject?.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if model.isLoadingProjects {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "folder")
                }
                Text(model.selectedProject?.name ?? String(localized: "Choose Project"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.glass)
        .disabled(
            !model.canChangeTarget || model.isLoadingProjects || model.availableProjects.isEmpty
        )
        .accessibilityLabel("Choose project")
        .accessibilityValue(model.selectedProject?.name ?? String(localized: "None"))
        .accessibilityIdentifier("new-chat-project")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if model.messages.isEmpty && model.permissions.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "Start a conversation", systemImage: "chevron.left.forwardslash.chevron.right"
                            )
                        } description: {
                            Text("Ask OpenCode to inspect, explain, or change this project.")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }

                    ForEach(model.messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }

                    ForEach(model.permissions) { permission in
                        PermissionCardView(permission: permission) { response in
                            Task { await model.respond(to: permission, with: response) }
                        }
                    }

                    Color.clear.frame(height: 1).id("transcript-bottom")
                }
                .frame(maxWidth: AppTheme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.standardPadding)
                .padding(.vertical, 22)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat-transcript")
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY <= 44
            } action: { _, nearBottom in
                isNearBottom = nearBottom
                if nearBottom {
                    shouldFollowLatest = true
                } else if isUserInteracting {
                    shouldFollowLatest = false
                }
            }
            .onScrollPhaseChange { _, phase in
                isUserInteracting = phase == .interacting || phase == .decelerating
                if isUserInteracting && !isNearBottom {
                    shouldFollowLatest = false
                }
            }
            .task(id: model.route?.id) {
                guard !hasPerformedInitialScroll else { return }
                await Task.yield()
                scrollToLatest(using: proxy, animated: false)
                hasPerformedInitialScroll = true
            }
            .onChange(of: model.messages) { _, _ in
                let sentOwnMessage = model.messages.last?.id.hasPrefix("temporary-user-") == true
                guard shouldFollowLatest || sentOwnMessage else { return }
                shouldFollowLatest = true
                scrollToLatest(using: proxy, animated: true)
            }
            .onChange(of: model.permissions) { _, _ in
                guard shouldFollowLatest else { return }
                scrollToLatest(using: proxy, animated: true)
            }
            .onChange(of: jumpToLatestRequest) { _, _ in
                scrollToLatest(using: proxy, animated: true)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Menu {
                    if !model.models.isEmpty {
                        Section("Model") {
                            Button("Use server default") { model.selectedModel = nil }
                            ForEach(model.models.filter(\.isConnected)) { option in
                                Button {
                                    model.selectedModel = option
                                } label: {
                                    if model.selectedModel?.id == option.id {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        }
                    }

                    if !model.agents.isEmpty {
                        Section("Agent") {
                            Button("Use server default") { model.selectedAgent = nil }
                            ForEach(model.agents) { option in
                                Button {
                                    model.selectedAgent = option
                                } label: {
                                    if model.selectedAgent?.id == option.id {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(model.route?.session.title ?? String(localized: "New Chat"))
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                if let serverName {
                    Text(serverName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .contain)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if !model.isNewChat {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New Chat")
                .accessibilityIdentifier("chat-new-chat")

                Menu {
                    Button(action: onTogglePin) {
                        Label(
                            isPinned ? "Unpin" : "Pin",
                            systemImage: isPinned ? "pin.slash" : "pin"
                        )
                    }

                    Button {
                        renameTitle = model.route?.session.title ?? ""
                        showsRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Divider()

                    Button(action: onOpenChanges) {
                        Label("Changes", systemImage: "arrow.triangle.branch")
                    }
                    Button(action: onOpenFiles) {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Conversation Options")
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        if animated && !accessibilityReduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("transcript-bottom", anchor: .bottom)
        }
    }
}

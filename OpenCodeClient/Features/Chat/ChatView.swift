import SwiftUI

struct ChatView: View {
    let model: ChatViewModel
    let onOpenSettings: () -> Void

    @Environment(\.scenePhase) private var scenePhase

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
        .navigationTitle(model.route?.session.title ?? String(localized: "Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposerView(model: model)
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
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.permissions) { _, _ in
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
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
                HStack(spacing: 6) {
                    Text(model.route?.session.title ?? String(localized: "Chat"))
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Circle()
                .fill(model.eventsConnected ? AppTheme.signal : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .accessibilityLabel(
                    model.eventsConnected ? "Live updates connected" : "Live updates reconnecting")

            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Settings")
        }
    }
}

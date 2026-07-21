import SwiftUI

struct ProjectsView: View {
    let appModel: AppModel
    let model: ProjectsViewModel
    let onSelect: (SessionRoute) -> Void
    let onOpenSettings: () -> Void

    @State private var createError: String?

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                LoadingStateView(title: "Loading projects…")
            case .loading where model.sections.isEmpty:
                LoadingStateView(title: "Loading projects…")
            case let .failed(message) where model.sections.isEmpty:
                ErrorStateView(title: "Couldn’t Load Projects", message: message) {
                    Task { await model.refresh() }
                }
            default:
                content
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ),
            prompt: "Search sessions"
        )
        .toolbar { toolbarContent }
        .alert(
            "Couldn’t Create Session",
            isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(createError ?? "")
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30, pinnedViews: []) {
                serverHeader

                if model.filteredSections.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    ForEach(model.filteredSections) { section in
                        projectSection(section)
                    }
                }
            }
            .padding(.horizontal, AppTheme.standardPadding)
            .padding(.bottom, 110)
        }
        .refreshable { await model.refresh() }
    }

    private var serverHeader: some View {
        HStack(spacing: 12) {
            AppMark(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(appModel.activeProfile?.name ?? String(localized: "OpenCode"))
                    .font(.headline)
                ConnectionLabel(
                    isConnected: model.health?.isHealthy == true,
                    text: model.health.map { "OpenCode \($0.version)" } ?? String(localized: "Connecting…")
                )
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func projectSection(_ section: ProjectSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.title3.weight(.medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.project.name)
                        .font(.title3.weight(.semibold))
                    Text(section.project.worktree)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    createSession(in: section.project)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.isCreatingSession)
                .accessibilityLabel("New session in \(section.project.name)")
            }
            .padding(.bottom, 4)

            if section.sessions.isEmpty {
                Button {
                    createSession(in: section.project)
                } label: {
                    Label("Start the first session", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(section.sessions) { session in
                    Button {
                        if let route = model.route(for: session, in: section.project) {
                            onSelect(route)
                        }
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session-\(session.id)")
                }
            }
        }
    }

    private func sessionRow(_ session: OpenCodeSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if session.parentID != nil {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(session.updatedAt, format: .relative(presentation: .named))
                    if let summary = session.summary, summary.files > 0 {
                        Text("\(summary.files) files")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            if model.statuses[session.id]?.isBusy == true {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.signal)
                    .accessibilityLabel("Agent working")
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(appModel.profiles) { profile in
                    Button {
                        Task { await appModel.activate(profileID: profile.id) }
                    } label: {
                        if profile.id == appModel.activeProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "server.rack")
            }
            .accessibilityLabel("Choose server")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh projects")

            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Settings")
        }
    }

    private func createSession(in project: OpenCodeProject) {
        Task {
            do {
                let route = try await model.createSession(in: project)
                onSelect(route)
            } catch {
                createError = error.localizedDescription
            }
        }
    }
}

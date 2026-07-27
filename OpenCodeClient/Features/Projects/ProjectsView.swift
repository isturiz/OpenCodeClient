import SwiftUI

struct ProjectsView: View {
    let appModel: AppModel
    let model: ProjectsViewModel
    let onSelect: (ConversationRoute) -> Void
    let onNewChat: (OpenCodeProject?) -> Void
    let onOpenSettings: () -> Void

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
        .task {
            model.organization = appModel.sessionOrganization
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                model.refreshChronologyReferenceDate()
            }
        }
        .onChange(of: appModel.sessionOrganization) { _, organization in
            model.organization = organization
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
                    organizedContent
                }
            }
            .padding(.horizontal, AppTheme.standardPadding)
            .padding(.bottom, AppTheme.standardPadding)
        }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var organizedContent: some View {
        switch model.organization {
        case .project:
            ForEach(model.filteredSections) { section in
                projectSection(section)
            }
        case .chronology:
            if model.chronologySections.isEmpty {
                emptySessionsView
            } else {
                ForEach(model.chronologySections) { section in
                    chronologySection(section, showsProject: true)
                }
            }
        case .projectThenChronology:
            ForEach(model.projectChronologySections) { section in
                projectChronologySection(section)
            }
        }
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
            projectHeader(section.project)

            if section.sessions.isEmpty {
                firstSessionButton(in: section.project)
            } else {
                ForEach(section.sessions) { session in
                    sessionButton(session, in: section.project, showsProject: false)
                }
            }
        }
    }

    private func projectChronologySection(_ section: ProjectChronologySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            projectHeader(section.project)

            if section.chronology.isEmpty {
                firstSessionButton(in: section.project)
            } else {
                ForEach(section.chronology) { chronology in
                    chronologySection(chronology, showsProject: false)
                }
            }
        }
    }

    private func projectHeader(_ project: OpenCodeProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title3.weight(.medium))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                Text(project.worktree)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onNewChat(project)
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("New session in \(project.name)")
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    private func firstSessionButton(in project: OpenCodeProject) -> some View {
        Button {
            onNewChat(project)
        } label: {
            Label("Start the first session", systemImage: "plus")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func chronologySection(
        _ section: SessionChronologySection,
        showsProject: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.bucket.title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ForEach(section.items) { item in
                sessionButton(item.session, in: item.project, showsProject: showsProject)
            }
        }
    }

    private func sessionButton(
        _ session: OpenCodeSession,
        in project: OpenCodeProject,
        showsProject: Bool
    ) -> some View {
        Button {
            if let route = model.route(for: session, in: project) {
                onSelect(route)
            }
        } label: {
            sessionRow(session, project: showsProject ? project : nil)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session-\(session.id)")
    }

    private func sessionRow(_ session: OpenCodeSession, project: OpenCodeProject?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if session.parentID != nil {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let project {
                    Text(project.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var emptySessionsView: some View {
        ContentUnavailableView {
            Label("No conversations", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Create a new chat to start a conversation in one of your projects.")
        } actions: {
            Button("New Chat") { onNewChat(nil) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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

            Menu {
                Menu {
                    Toggle("Project", isOn: projectGroupingBinding)
                        .disabled(model.organization == .project)
                        .accessibilityHint("At least one organization option must remain enabled.")
                    Toggle("Chronology", isOn: chronologyGroupingBinding)
                        .disabled(model.organization == .chronology)
                        .accessibilityHint("At least one organization option must remain enabled.")
                } label: {
                    Label("Organize", systemImage: "arrow.up.arrow.down")
                }

                Divider()

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More Options")
        }

        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                onNewChat(nil)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New Chat")
            .accessibilityIdentifier("new-chat")
        }
    }

    private var projectGroupingBinding: Binding<Bool> {
        Binding(
            get: { model.organization.groupsByProject },
            set: { setOrganization(model.organization.settingProjectGrouping($0)) }
        )
    }

    private var chronologyGroupingBinding: Binding<Bool> {
        Binding(
            get: { model.organization.groupsByChronology },
            set: { setOrganization(model.organization.settingChronologyGrouping($0)) }
        )
    }

    private func setOrganization(_ organization: SessionOrganization) {
        model.organization = organization
        Task {
            await appModel.saveSessionOrganization(organization)
            model.organization = appModel.sessionOrganization
        }
    }
}

private extension SessionChronologyBucket {
    var title: LocalizedStringResource {
        switch self {
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .previousSevenDays:
            "Previous 7 Days"
        case .earlier:
            "Earlier"
        }
    }
}

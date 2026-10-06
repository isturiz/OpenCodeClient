import SwiftUI

struct ChangesView: View {
    @State private var model: ChangesViewModel

    init(sessionID: String, directory: String, client: any OpenCodeClientProtocol) {
        _model = State(
            initialValue: ChangesViewModel(
                sessionID: sessionID,
                directory: directory,
                client: client
            )
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                LoadingStateView(title: "Loading changes…")
            case .loading where model.changes.isEmpty:
                LoadingStateView(title: "Loading changes…")
            case let .failed(message) where model.changes.isEmpty:
                ErrorStateView(title: "Couldn’t Load Changes", message: message) {
                    Task { await model.load() }
                }
            case .loaded where model.changes.isEmpty:
                ContentUnavailableView {
                    Label("No Changes", systemImage: "checkmark.circle")
                } description: {
                    Text("This session has no file changes to review.")
                }
            default:
                changesList
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
    }

    private var changesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.changes) { change in
                    NavigationLink {
                        ChangeDetailView(change: change)
                    } label: {
                        ChangeRow(change: change)
                    }
                    .buttonStyle(.plain)

                    if change.id != model.changes.last?.id {
                        Divider().foregroundStyle(AppTheme.divider)
                    }
                }
            }
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.standardPadding)
            .padding(.vertical, AppTheme.compactPadding)
        }
        .refreshable { await model.load() }
    }
}

private struct ChangeRow: View {
    let change: OpenCodeFileDiff

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: change.status.systemImage)
                .foregroundStyle(change.status.color)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(change.path.isEmpty ? String(localized: "Unknown file") : change.path)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(change.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("+\(change.additions)")
                    .foregroundStyle(AppTheme.signal)
                Text("−\(change.deletions)")
                    .foregroundStyle(AppTheme.warning)
            }
            .font(.callout.monospacedDigit())

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: AppTheme.minimumHitTarget)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(change.path), \(change.status.accessibilityTitle), \(change.additions) additions, \(change.deletions) deletions"
        )
    }
}

private struct ChangeDetailView: View {
    let change: OpenCodeFileDiff

    var body: some View {
        Group {
            if let patch = change.rawPatch {
                ScrollView([.horizontal, .vertical]) {
                    Text(patch)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(AppTheme.standardPadding)
                }
            } else {
                ContentUnavailableView {
                    Label("Patch Unavailable", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("The server did not return patch content for this file.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
        .navigationTitle(change.path.isEmpty ? String(localized: "Change") : change.path)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension OpenCodeFileDiffStatus {
    var title: LocalizedStringResource {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .unknown: "Changed"
        }
    }

    var accessibilityTitle: String {
        String(localized: title)
    }

    var systemImage: String {
        switch self {
        case .added: "plus.circle"
        case .modified: "pencil.circle"
        case .deleted: "minus.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .added: AppTheme.signal
        case .deleted: AppTheme.warning
        case .modified, .unknown: .secondary
        }
    }
}

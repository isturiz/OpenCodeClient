import SwiftUI

struct FilesView: View {
    @State private var model: FilesViewModel

    private let client: any OpenCodeClientProtocol

    init(
        directory: String,
        path: String = "",
        client: any OpenCodeClientProtocol
    ) {
        self.client = client
        _model = State(
            initialValue: FilesViewModel(directory: directory, path: path, client: client)
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                LoadingStateView(title: "Loading files…")
            case .loading where model.nodes.isEmpty:
                LoadingStateView(title: "Loading files…")
            case let .failed(message) where model.nodes.isEmpty:
                ErrorStateView(title: "Couldn’t Load Files", message: message) {
                    Task { await model.load() }
                }
            case .loaded where model.nodes.isEmpty:
                ContentUnavailableView {
                    Label("Empty Folder", systemImage: "folder")
                } description: {
                    Text("This folder does not contain any visible files.")
                }
            default:
                fileList
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.nodes) { node in
                    destination(for: node)

                    if node.id != model.nodes.last?.id {
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

    @ViewBuilder
    private func destination(for node: OpenCodeFileNode) -> some View {
        switch node.type {
        case .directory:
            NavigationLink {
                FilesView(directory: model.directory, path: node.path, client: client)
            } label: {
                FileNodeRow(node: node, showsDisclosure: true)
            }
            .buttonStyle(.plain)
        case .file:
            NavigationLink {
                FileContentView(directory: model.directory, path: node.path, client: client)
            } label: {
                FileNodeRow(node: node, showsDisclosure: true)
            }
            .buttonStyle(.plain)
        case .unknown:
            FileNodeRow(node: node, showsDisclosure: false)
        }
    }

    private var navigationTitle: String {
        guard !model.path.isEmpty else { return String(localized: "Files") }
        let name = URL(fileURLWithPath: model.path).lastPathComponent
        return name.isEmpty ? model.path : name
    }
}

private struct FileNodeRow: View {
    let node: OpenCodeFileNode
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.type.systemImage)
                .font(.title3)
                .foregroundStyle(node.type == .directory ? AppTheme.signal : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.name.isEmpty ? String(localized: "Unknown item") : node.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if case let .unknown(type) = node.type {
                    Text(type.isEmpty ? String(localized: "Unsupported item") : type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: AppTheme.minimumHitTarget)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct FileContentView: View {
    @State private var model: FileContentViewModel

    init(directory: String, path: String, client: any OpenCodeClientProtocol) {
        _model = State(
            initialValue: FileContentViewModel(directory: directory, path: path, client: client)
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                LoadingStateView(title: "Loading file…")
            case let .failed(message):
                ErrorStateView(title: "Couldn’t Load File", message: message) {
                    Task { await model.load() }
                }
            case .loaded:
                content
            }
        }
        .background(AppTheme.canvas)
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if let fileContent = model.fileContent {
            switch fileContent.type {
            case .text:
                if let text = fileContent.content {
                    ScrollView([.horizontal, .vertical]) {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(AppTheme.standardPadding)
                    }
                    .refreshable { await model.load() }
                } else {
                    ContentUnavailableView {
                        Label("Content Unavailable", systemImage: "doc.text")
                    } description: {
                        Text("The server returned no text for this file.")
                    }
                }
            case .binary:
                ContentUnavailableView {
                    Label("Binary File", systemImage: "doc.zipper")
                } description: {
                    Text("Binary file contents cannot be displayed.")
                }
            case let .unknown(type):
                ContentUnavailableView {
                    Label("Unsupported File", systemImage: "questionmark.folder")
                } description: {
                    if type.isEmpty {
                        Text("The server returned an unsupported content type.")
                    } else {
                        Text("The server returned the unsupported content type “\(type)”.")
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Content Unavailable", systemImage: "doc.text")
            }
        }
    }

    private var fileName: String {
        let name = URL(fileURLWithPath: model.path).lastPathComponent
        return name.isEmpty ? model.path : name
    }
}

private extension OpenCodeFileNodeType {
    var systemImage: String {
        switch self {
        case .directory: "folder"
        case .file: "doc"
        case .unknown: "questionmark.folder"
        }
    }
}

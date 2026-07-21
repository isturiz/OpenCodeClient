import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .assistant, .unknown:
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.signal)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.parts) { part in
                    if let text = part.plainText, !text.isEmpty {
                        Text(text)
                            .font(.body.weight(.medium))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                messageMetadata
            }
            .padding(14)
        }
        .background(AppTheme.signalMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("user-message-\(message.id)")
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AppMark(size: 26)
                Text("OpenCode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(message.parts) { part in
                partView(part)
            }

            if let error = message.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            messageMetadata
        }
        .accessibilityIdentifier("assistant-message-\(message.id)")
    }

    @ViewBuilder
    private func partView(_ part: MessagePart) -> some View {
        switch part {
        case let .text(_, text, synthetic):
            if !text.isEmpty && !synthetic {
                MarkdownContentView(markdown: text)
            }
        case let .reasoning(_, text):
            if !text.isEmpty {
                DisclosureGroup("Reasoning") {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
                .font(.callout.weight(.medium))
                .tint(.secondary)
            }
        case let .tool(call):
            ToolCallView(call: call)
        case let .file(_, filename, mime, _):
            Label(filename ?? mime, systemImage: "doc")
                .font(.callout.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
        case let .patch(_, files):
            VStack(alignment: .leading, spacing: 8) {
                Label("Files changed", systemImage: "arrow.triangle.branch")
                    .font(.callout.weight(.medium))
                ForEach(files, id: \.self) { file in
                    Text(file)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
        case .unknown:
            EmptyView()
        }
    }

    private var messageMetadata: some View {
        HStack(spacing: 6) {
            if let provider = message.providerID, let model = message.modelID {
                Text("\(provider)/\(model)")
            }
            Text(message.createdAt, format: .dateTime.hour().minute())
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.tertiary)
    }
}

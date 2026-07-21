import SwiftUI

struct ToolCallView: View {
    let call: ToolCall
    @State private var isExpanded: Bool

    init(call: ToolCall) {
        self.call = call
        _isExpanded = State(initialValue: call.status == .running || call.status == .error)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let input = call.input?.prettyPrinted, !input.isEmpty {
                    detailBlock(title: "Input", content: input)
                }
                if let output = call.output, !output.isEmpty {
                    detailBlock(title: "Output", content: output)
                }
                if let error = call.error, !error.isEmpty {
                    detailBlock(title: "Error", content: error)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.title ?? call.tool)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if call.title != nil {
                        Text(call.tool)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .tint(.secondary)
        .padding(14)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("tool-call-\(call.id)")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch call.status {
        case .pending, .running:
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.signal)
        case .completed:
            Image(systemName: "checkmark")
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark")
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.secondary)
        }
    }

    private func detailBlock(title: LocalizedStringKey, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(content)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

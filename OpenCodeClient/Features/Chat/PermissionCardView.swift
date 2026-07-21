import SwiftUI

struct PermissionCardView: View {
    let permission: PermissionRequest
    let respond: (PermissionResponse) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.warning)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 12) {
                Label("Permission Required", systemImage: "hand.raised")
                    .font(.headline)
                Text(permission.title)
                    .font(.body)

                if !permission.patterns.isEmpty {
                    Text(permission.patterns.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                ViewThatFits {
                    HStack { actionButtons }
                    VStack(alignment: .leading) { actionButtons }
                }
            }
            .padding(16)
        }
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("permission-\(permission.id)")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Allow Once") { respond(.once) }
            .buttonStyle(.glassProminent)
        Button("Always Allow") { respond(.always) }
            .buttonStyle(.glass)
        Button("Reject", role: .destructive) { respond(.reject) }
            .buttonStyle(.glass)
    }
}

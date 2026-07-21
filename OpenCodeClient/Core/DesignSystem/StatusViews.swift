import SwiftUI

struct ConnectionLabel: View {
    let isConnected: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Circle()
                .fill(isConnected ? AppTheme.signal : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let title: LocalizedStringKey
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.glass)
            }
        }
    }
}

struct LoadingStateView: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

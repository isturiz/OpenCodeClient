import SwiftUI

struct SettingsView: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var serverEditor: ServerEditorPresentation?
    @State private var voiceEditor: VoiceEditorPresentation?
    @State private var presentedError: String?
    @State private var pendingDeletion: PendingDeletion?

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                voiceSection
                helpSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $serverEditor) { presentation in
                ServerEditorView(appModel: appModel, profile: presentation.profile)
            }
            .sheet(item: $voiceEditor) { presentation in
                VoiceEditorView(appModel: appModel, profile: presentation.profile)
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(
                    get: { presentedError != nil },
                    set: { if !$0 { presentedError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(presentedError ?? "")
            }
            .confirmationDialog(
                "Delete Configuration?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { confirmDeletion() }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("This removes the saved configuration and its Keychain credential.")
            }
        }
    }

    private var serverSection: some View {
        Section {
            ForEach(appModel.profiles) { profile in
                HStack(spacing: 10) {
                    Button {
                        Task { await appModel.activate(profileID: profile.id) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(
                                    profile.id == appModel.activeProfileID ? AppTheme.signal : .secondary
                                )
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if profile.id == appModel.activeProfileID {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.signal)
                            .accessibilityLabel("Active server")
                    }

                    Button {
                        serverEditor = ServerEditorPresentation(profile: profile)
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(
                                width: AppTheme.minimumHitTarget,
                                height: AppTheme.minimumHitTarget
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(profile.name)")
                }
                .swipeActions(allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = .server(profile.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                serverEditor = ServerEditorPresentation(profile: nil)
            } label: {
                Label("Add OpenCode Server", systemImage: "plus")
            }
        } header: {
            Text("OpenCode Servers")
        } footer: {
            Text("Switching servers clears the visible workspace and establishes a new event stream.")
        }
    }

    private var voiceSection: some View {
        Section {
            Button {
                Task { await appModel.activateVoiceProfile(profileID: nil) }
            } label: {
                HStack {
                    Label("None", systemImage: "mic.slash")
                        .foregroundStyle(.primary)
                    Spacer()
                    if appModel.activeVoiceProfileID == nil {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.signal)
                    }
                }
            }

            ForEach(appModel.voiceProfiles) { profile in
                HStack(spacing: 10) {
                    Button {
                        Task { await appModel.activateVoiceProfile(profileID: profile.id) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "waveform")
                                .foregroundStyle(
                                    profile.id == appModel.activeVoiceProfileID
                                        ? AppTheme.signal : .secondary
                                )
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if profile.id == appModel.activeVoiceProfileID {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.signal)
                            .accessibilityLabel("Active voice server")
                    }

                    Button {
                        voiceEditor = VoiceEditorPresentation(profile: profile)
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(
                                width: AppTheme.minimumHitTarget,
                                height: AppTheme.minimumHitTarget
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(profile.name)")
                }
                .swipeActions(allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = .voice(profile.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                voiceEditor = VoiceEditorPresentation(profile: nil)
            } label: {
                Label("Add Voice Server", systemImage: "plus")
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Select the voice server used for dictation, or choose None to disable voice.")
        }
    }

    private var helpSection: some View {
        Section("Help") {
            Link(
                "OpenCode Server Setup",
                destination: URL(
                    string:
                        "https://github.com/isturiz/OpenCodeClient/blob/main/docs/SETUP.md"
                        + "#opencode-on-a-trusted-lan"
                )!
            )
            Link(
                "FluidVoice Setup",
                destination: URL(
                    string: "https://github.com/isturiz/OpenCodeClient/blob/main/docs/SETUP.md#fluidvoice"
                )!
            )
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "OpenCode Client")
            Link("OpenCode Documentation", destination: URL(string: "https://opencode.ai/docs/server/")!)
            Text("Independent community project. Not affiliated with the OpenCode team.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteServer(_ profileID: UUID) {
        Task {
            do {
                try await appModel.delete(profileID: profileID)
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func deleteVoiceProfile(_ profileID: UUID) {
        Task {
            do {
                try await appModel.deleteVoiceProfile(profileID: profileID)
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func confirmDeletion() {
        let deletion = pendingDeletion
        pendingDeletion = nil
        switch deletion {
        case let .server(profileID):
            deleteServer(profileID)
        case let .voice(profileID):
            deleteVoiceProfile(profileID)
        case nil:
            break
        }
    }
}

private struct ServerEditorPresentation: Identifiable {
    let id = UUID()
    let profile: ServerProfile?
}

private struct VoiceEditorPresentation: Identifiable {
    let id = UUID()
    let profile: VoiceProfile?
}

private enum PendingDeletion {
    case server(UUID)
    case voice(UUID)
}

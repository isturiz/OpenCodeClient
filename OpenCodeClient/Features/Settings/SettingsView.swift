import SwiftUI

struct SettingsView: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var showsServerEditor = false
    @State private var editedProfile: ServerProfile?
    @State private var voiceBaseURL = ""
    @State private var voiceUsername = ""
    @State private var voicePassword = ""
    @State private var usesPostProcessing = false
    @State private var voiceHealth: FluidVoiceHealth?
    @State private var voiceError: String?
    @State private var isTestingVoice = false
    @State private var isSavingVoice = false

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                voiceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsServerEditor) {
                ServerEditorView(appModel: appModel, profile: editedProfile)
            }
            .task {
                voiceBaseURL = appModel.voiceConfiguration.baseURL
                voiceUsername = appModel.voiceConfiguration.username
                voicePassword = (try? await appModel.fluidVoicePassword()) ?? ""
                usesPostProcessing = appModel.voiceConfiguration.usesPostProcessing
            }
        }
    }

    private var serverSection: some View {
        Section {
            ForEach(appModel.profiles) { profile in
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
                        Spacer()
                        if profile.id == appModel.activeProfileID {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.signal)
                                .accessibilityLabel("Active server")
                        }
                        Button {
                            editedProfile = profile
                            showsServerEditor = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(profile.name)")
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await appModel.delete(profileID: profile.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                editedProfile = nil
                showsServerEditor = true
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
            TextField("FluidVoice URL", text: $voiceBaseURL, prompt: Text("https://mac.example.ts.net"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("fluidvoice-url")

            TextField("Username", text: $voiceUsername)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("fluidvoice-username")

            SecureField("Password", text: $voicePassword)
                .textContentType(.password)
                .accessibilityIdentifier("fluidvoice-password")

            Toggle("Post-process with Fluid Intelligence", isOn: $usesPostProcessing)

            Button {
                testVoice()
            } label: {
                HStack {
                    Label("Test FluidVoice", systemImage: "waveform")
                    Spacer()
                    if isTestingVoice {
                        ProgressView()
                    } else if voiceHealth?.isHealthy == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.signal)
                    }
                }
            }
            .disabled(voiceBaseURL.trimmed.isEmpty || isTestingVoice)

            Button("Save Voice Settings") {
                saveVoice()
            }
            .disabled(isSavingVoice)

            if let voiceHealth {
                LabeledContent("FluidVoice Version", value: voiceHealth.version)
            }
            if let voiceError {
                Text(voiceError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(
                "Use an HTTPS reverse proxy or Tailscale URL. Optional Basic Auth credentials are stored in Keychain. FluidVoice's port 47733 must remain loopback-only on the Mac."
            )
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "OpenCode Client")
            LabeledContent("Compatibility", value: "OpenCode 1.18.3")
            Link("OpenCode Documentation", destination: URL(string: "https://opencode.ai/docs/server/")!)
            Text("Independent community project. Not affiliated with the OpenCode team.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func testVoice() {
        isTestingVoice = true
        voiceHealth = nil
        voiceError = nil
        Task {
            defer { isTestingVoice = false }
            do {
                voiceHealth = try await appModel.testFluidVoice(
                    baseURL: voiceBaseURL,
                    username: voiceUsername,
                    password: voicePassword
                )
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }

    private func saveVoice() {
        isSavingVoice = true
        voiceError = nil
        Task {
            defer { isSavingVoice = false }
            do {
                try await appModel.saveVoiceConfiguration(
                    VoiceConfiguration(
                        baseURL: voiceBaseURL,
                        username: voiceUsername,
                        usesPostProcessing: usesPostProcessing
                    ),
                    password: voicePassword
                )
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

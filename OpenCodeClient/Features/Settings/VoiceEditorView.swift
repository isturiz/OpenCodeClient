import SwiftUI

struct VoiceEditorView: View {
    let appModel: AppModel
    let profile: VoiceProfile?
    private let draftID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var baseURL: String
    @State private var username: String
    @State private var password = ""
    @State private var usesPostProcessing: Bool
    @State private var isLoadingCredential: Bool
    @State private var credentialLoadFailed = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: FluidVoiceHealth?
    @State private var errorMessage: String?
    @State private var testGeneration = UUID()

    init(appModel: AppModel, profile: VoiceProfile? = nil) {
        self.appModel = appModel
        self.profile = profile
        draftID = profile?.id ?? UUID()
        _name = State(initialValue: profile?.name ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
        _username = State(initialValue: profile?.username ?? "")
        _usesPostProcessing = State(initialValue: profile?.usesPostProcessing ?? false)
        _isLoadingCredential = State(initialValue: profile != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice Server") {
                    TextField("Name", text: $name, prompt: Text("Studio Mac"))
                        .textContentType(.organizationName)
                        .accessibilityIdentifier("voice-name")

                    TextField("FluidVoice URL", text: $baseURL, prompt: Text("https://voice.example.com"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("fluidvoice-url")
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("fluidvoice-username")

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .disabled(isLoadingCredential || credentialLoadFailed)
                        .accessibilityIdentifier("fluidvoice-password")

                    if isLoadingCredential {
                        HStack {
                            Text("Loading credential…")
                            Spacer()
                            ProgressView()
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Basic Authentication")
                } footer: {
                    Text(
                        "The password is stored in Keychain and is never written to project files or UserDefaults."
                    )
                }

                Section {
                    Toggle("Post-process with Fluid Intelligence", isOn: $usesPostProcessing)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test FluidVoice", systemImage: "waveform")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if testResult?.isHealthy == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.signal)
                            }
                        }
                    }
                    .disabled(
                        isLoadingCredential || credentialLoadFailed || isTesting
                            || baseURL.trimmed.isEmpty
                    )
                    .accessibilityIdentifier("test-voice-connection")

                    if let testResult {
                        LabeledContent("FluidVoice Version", value: testResult.version)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("voice-error")
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Voice Server" : "Edit Voice Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            isLoadingCredential || credentialLoadFailed || name.trimmed.isEmpty
                                || baseURL.trimmed.isEmpty || isSaving
                        )
                        .accessibilityIdentifier("save-voice")
                }
            }
            .task {
                guard let profile else { return }
                defer { isLoadingCredential = false }
                do {
                    password = try await appModel.voicePassword(for: profile.id)
                } catch {
                    credentialLoadFailed = true
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: name) { _, _ in clearTestResult() }
            .onChange(of: baseURL) { _, _ in clearTestResult() }
            .onChange(of: username) { _, _ in clearTestResult() }
            .onChange(of: password) { _, _ in clearTestResult() }
        }
    }

    private var draftProfile: VoiceProfile {
        VoiceProfile(
            id: draftID,
            name: name,
            baseURL: baseURL,
            username: username,
            usesPostProcessing: usesPostProcessing,
            createdAt: profile?.createdAt ?? .now
        )
    }

    private func testConnection() {
        let requestedGeneration = UUID()
        testGeneration = requestedGeneration
        isTesting = true
        testResult = nil
        errorMessage = nil
        Task {
            defer { isTesting = false }
            do {
                let health = try await appModel.testVoice(profile: draftProfile, password: password)
                guard testGeneration == requestedGeneration else { return }
                testResult = health
                if !health.isHealthy {
                    errorMessage = String(localized: "FluidVoice reported an unhealthy status.")
                }
            } catch {
                guard testGeneration == requestedGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await appModel.saveVoiceProfile(draftProfile, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearTestResult() {
        testGeneration = UUID()
        if !isTesting {
            testResult = nil
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

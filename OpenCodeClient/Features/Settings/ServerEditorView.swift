import SwiftUI

struct ServerEditorView: View {
    let appModel: AppModel
    let profile: ServerProfile?
    var makeActive = false

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var baseURL: String
    @State private var username: String
    @State private var password = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: OpenCodeHealth?
    @State private var errorMessage: String?

    init(appModel: AppModel, profile: ServerProfile? = nil, makeActive: Bool = false) {
        self.appModel = appModel
        self.profile = profile
        self.makeActive = makeActive
        _name = State(initialValue: profile?.name ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
        _username = State(initialValue: profile?.username ?? "opencode")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Home Mac"))
                        .textContentType(.organizationName)
                        .accessibilityIdentifier("server-name")

                    TextField("URL", text: $baseURL, prompt: Text("https://mac.example.ts.net"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("server-url")
                } header: {
                    Text("Server")
                } footer: {
                    Text("Use HTTPS outside a trusted local network. OpenCode usually listens on port 4096.")
                }

                Section {
                    TextField("Username", text: $username, prompt: Text("opencode"))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("server-username")

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("server-password")
                } header: {
                    Text("Basic Authentication")
                } footer: {
                    Text(
                        "The password is stored in Keychain and is never written to project files or UserDefaults."
                    )
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "network")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if testResult?.isHealthy == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.signal)
                            }
                        }
                    }
                    .disabled(isTesting || baseURL.isEmpty)
                    .accessibilityIdentifier("test-server-connection")

                    if let testResult {
                        LabeledContent("OpenCode Version", value: testResult.version)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("server-error")
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmed.isEmpty || baseURL.trimmed.isEmpty || isSaving)
                        .accessibilityIdentifier("save-server")
                }
            }
            .task {
                guard let profile else { return }
                password = (try? await appModel.password(for: profile.id)) ?? ""
            }
        }
    }

    private var draftProfile: ServerProfile {
        ServerProfile(
            id: profile?.id ?? UUID(),
            name: name,
            baseURL: baseURL,
            username: username,
            createdAt: profile?.createdAt ?? .now
        )
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        errorMessage = nil
        Task {
            defer { isTesting = false }
            do {
                let health = try await appModel.test(profile: draftProfile, password: password)
                testResult = health
                if !health.isHealthy {
                    errorMessage = String(localized: "OpenCode reported an unhealthy status.")
                }
            } catch {
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
                try await appModel.save(profile: draftProfile, password: password, makeActive: makeActive)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
    import Foundation

    extension AppDependencies {
        static let uiTestWorkspace: AppDependencies = {
            let profile = ServerProfile(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "Studio Mac",
                baseURL: "https://fixture.example.com",
                username: "opencode"
            )
            let settings = FixtureSettingsStore(
                snapshot: SettingsSnapshot(
                    profiles: [profile],
                    activeProfileID: profile.id,
                    voice: .empty
                )
            )
            let client = FixtureOpenCodeClient()
            return AppDependencies(
                settings: settings,
                makeOpenCodeClient: { _ in client },
                makeFluidVoiceClient: { _ in FixtureFluidVoiceClient() }
            )
        }()

        static let uiTestEmpty = AppDependencies(
            settings: FixtureSettingsStore(
                snapshot: SettingsSnapshot(profiles: [], activeProfileID: nil, voice: .empty)
            ),
            makeOpenCodeClient: { _ in FixtureOpenCodeClient() },
            makeFluidVoiceClient: { _ in FixtureFluidVoiceClient() }
        )
    }

    private actor FixtureSettingsStore: SettingsStoring {
        private var value: SettingsSnapshot
        private var passwords: [UUID: String] = [:]
        private var voicePassword: String?

        init(snapshot: SettingsSnapshot) {
            value = snapshot
        }

        func snapshot() -> SettingsSnapshot { value }

        func upsert(_ profile: ServerProfile, password: String?) {
            value.profiles.removeAll { $0.id == profile.id }
            value.profiles.append(profile)
            value.activeProfileID = value.activeProfileID ?? profile.id
            if let password { passwords[profile.id] = password }
        }

        func delete(profileID: UUID) {
            value.profiles.removeAll { $0.id == profileID }
            if value.activeProfileID == profileID { value.activeProfileID = value.profiles.first?.id }
        }

        func setActive(profileID: UUID?) { value.activeProfileID = profileID }
        func password(for profileID: UUID) -> String? { passwords[profileID] }
        func fluidVoicePassword() -> String? { voicePassword }
        func saveVoiceConfiguration(_ configuration: VoiceConfiguration, password: String?) {
            value.voice = configuration
            if let password { voicePassword = password.isEmpty ? nil : password }
        }
    }

    private actor FixtureOpenCodeClient: OpenCodeClientProtocol {
        private let project = OpenCodeProject(
            id: "fixture-project",
            worktree: "/Users/demo/Projects/OpenCodeClient",
            vcs: "git"
        )
        private let session = OpenCodeSession(
            id: "fixture-session",
            projectID: "fixture-project",
            directory: "/Users/demo/Projects/OpenCodeClient",
            parentID: nil,
            title: "Build the native iOS client",
            version: "1.18.3",
            createdAt: .now.addingTimeInterval(-3_600),
            updatedAt: .now,
            summary: .init(additions: 142, deletions: 18, files: 8)
        )

        func health() -> OpenCodeHealth { OpenCodeHealth(isHealthy: true, version: "1.18.3") }
        func projects() -> [OpenCodeProject] { [project] }
        func sessions(directory: String) -> [OpenCodeSession] { [session] }
        func sessionStatuses(directory: String) -> [String: OpenCodeSessionStatus] { [session.id: .idle] }
        func createSession(directory: String, title: String?) -> OpenCodeSession { session }

        func messages(sessionID: String, directory: String, limit: Int?) -> [ChatMessage] {
            [
                ChatMessage(
                    id: "fixture-user-message",
                    sessionID: session.id,
                    role: .user,
                    createdAt: .now.addingTimeInterval(-60),
                    completedAt: .now.addingTimeInterval(-60),
                    providerID: "openai",
                    modelID: "gpt-5.6-sol",
                    errorMessage: nil,
                    parts: [
                        .text(
                            id: "fixture-user-text",
                            text: "Create a polished native iOS client for OpenCode.",
                            synthetic: false
                        )
                    ]
                ),
                ChatMessage(
                    id: "fixture-assistant-message",
                    sessionID: session.id,
                    role: .assistant,
                    createdAt: .now.addingTimeInterval(-55),
                    completedAt: .now.addingTimeInterval(-5),
                    providerID: "openai",
                    modelID: "gpt-5.6-sol",
                    errorMessage: nil,
                    parts: [
                        .text(
                            id: "fixture-assistant-text",
                            text:
                                "## Foundation complete\n\nThe project now has a maintainable architecture and a real-time chat surface.",
                            synthetic: false
                        ),
                        .tool(
                            ToolCall(
                                id: "fixture-tool",
                                callID: "call_fixture",
                                tool: "xcodebuild",
                                status: .completed,
                                title: "Built the iOS target",
                                input: .object(["scheme": .string("OpenCodeClient")]),
                                output: "BUILD SUCCEEDED",
                                error: nil
                            )
                        ),
                    ]
                ),
            ]
        }

        func promptAsync(
            sessionID: String,
            directory: String,
            text: String,
            model: ModelOption?,
            agent: AgentOption?
        ) {}

        func abort(sessionID: String, directory: String) {}

        func models(directory: String) -> [ModelOption] {
            [
                ModelOption(
                    providerID: "openai",
                    modelID: "gpt-5.6-sol",
                    providerName: "OpenAI",
                    name: "GPT-5.6 Sol",
                    isConnected: true
                )
            ]
        }

        func agents(directory: String) -> [AgentOption] {
            [AgentOption(name: "build", description: "Default build agent", mode: "primary", isBuiltIn: true)]
        }

        func reply(to permission: PermissionRequest, response: PermissionResponse, directory: String) {}

        func events() -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
            AsyncThrowingStream { _ in }
        }
    }

    private actor FixtureFluidVoiceClient: FluidVoiceClientProtocol {
        func health() -> FluidVoiceHealth { FluidVoiceHealth(status: "ok", version: "1.6.4") }
        func transcribe(fileURL: URL) -> FluidVoiceTranscription {
            FluidVoiceTranscription(
                text: "Fixture transcript", confidence: 1, sampleCount: 16_000, provider: "Fixture")
        }
        func postprocess(text: String) -> String { text }
        func transcribe(fileURL: URL, postprocess: Bool) -> String { "Fixture transcript" }
    }
#endif

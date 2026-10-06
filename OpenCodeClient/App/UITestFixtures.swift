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
                    activeProfileID: profile.id
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
                snapshot: SettingsSnapshot(profiles: [], activeProfileID: nil)
            ),
            makeOpenCodeClient: { _ in FixtureOpenCodeClient() },
            makeFluidVoiceClient: { _ in FixtureFluidVoiceClient() }
        )
    }

    private actor FixtureSettingsStore: SettingsStoring {
        private var value: SettingsSnapshot
        private var passwords: [UUID: String] = [:]
        private var voicePasswords: [UUID: String] = [:]

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

        func upsertVoiceProfile(_ profile: VoiceProfile, password: String?) {
            value.voiceProfiles.removeAll { $0.id == profile.id }
            value.voiceProfiles.append(profile)
            if let password { voicePasswords[profile.id] = password.isEmpty ? nil : password }
        }

        func deleteVoiceProfile(profileID: UUID) {
            value.voiceProfiles.removeAll { $0.id == profileID }
            voicePasswords[profileID] = nil
            if value.activeVoiceProfileID == profileID { value.activeVoiceProfileID = nil }
        }

        func setActiveVoiceProfile(profileID: UUID?) {
            value.activeVoiceProfileID = profileID
        }

        func voicePassword(for profileID: UUID) -> String? {
            voicePasswords[profileID]
        }

        func saveSessionOrganization(_ organization: SessionOrganization) {
            value.sessionOrganization = organization
        }

        func savePinnedSessions(_ references: Set<PinnedSessionReference>) {
            value.pinnedSessions = references
        }
    }

    private actor FixtureOpenCodeClient: OpenCodeClientProtocol {
        private let project = OpenCodeProject(
            id: "fixture-project",
            worktree: "/Users/demo/Projects/OpenCodeClient",
            vcs: "git"
        )
        private var session = OpenCodeSession(
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
        private let childSession = OpenCodeSession(
            id: "fixture-child-session",
            projectID: "fixture-project",
            directory: "/Users/demo/Projects/OpenCodeClient",
            parentID: "fixture-session",
            title: "Hidden fixture subagent",
            version: "1.18.3",
            createdAt: .now.addingTimeInterval(-1_800),
            updatedAt: .now.addingTimeInterval(-10),
            summary: nil
        )

        func health() -> OpenCodeHealth { OpenCodeHealth(isHealthy: true, version: "2.0.0") }
        func projects() -> [OpenCodeProject] { [project] }
        func sessions(directory: String) -> [OpenCodeSession] { [session, childSession] }
        func session(sessionID: String, directory: String) -> OpenCodeSession { session }
        func sessionStatuses(directory: String) -> [String: OpenCodeSessionStatus] { [session.id: .idle] }
        func createSession(directory: String, title: String?) -> OpenCodeSession { session }

        func updateSessionTitle(
            sessionID: String,
            directory: String,
            title: String
        ) -> OpenCodeSession {
            session = OpenCodeSession(
                id: session.id,
                projectID: session.projectID,
                directory: session.directory,
                parentID: session.parentID,
                title: title,
                version: session.version,
                createdAt: session.createdAt,
                updatedAt: .now,
                summary: session.summary
            )
            return session
        }

        func sessionDiff(sessionID: String, directory: String) -> [OpenCodeFileDiff] {
            [
                OpenCodeFileDiff(
                    path: "OpenCodeClient/App/AppShellView.swift",
                    status: .modified,
                    additions: 24,
                    deletions: 6,
                    patch: "@@ -1,2 +1,2 @@\n-import SwiftUI\n+import SwiftUI",
                    before: nil,
                    after: nil
                )
            ]
        }

        func files(directory: String, path: String) -> [OpenCodeFileNode] {
            if path.isEmpty {
                return [
                    OpenCodeFileNode(
                        name: "OpenCodeClient",
                        path: "OpenCodeClient",
                        absolutePath: nil,
                        type: .directory,
                        isIgnored: false
                    ),
                    OpenCodeFileNode(
                        name: "README.md",
                        path: "README.md",
                        absolutePath: nil,
                        type: .file,
                        isIgnored: false
                    ),
                ]
            }
            return [
                OpenCodeFileNode(
                    name: "OpenCodeClientApp.swift",
                    path: "OpenCodeClient/OpenCodeClientApp.swift",
                    absolutePath: nil,
                    type: .file,
                    isIgnored: false
                )
            ]
        }

        func fileContent(directory: String, path: String) -> OpenCodeFileContent {
            OpenCodeFileContent(type: .text, content: "# OpenCode Client\n\nNative iOS companion.")
        }

        func messages(sessionID: String, directory: String, limit: Int?) -> [ChatMessage] {
            let earlierMessages = (0..<12).map { index in
                let role: ChatRole = index.isMultiple(of: 2) ? .user : .assistant
                let text =
                    "History message \(index). This fixture content is deliberately long enough to require transcript scrolling."
                return ChatMessage(
                    id: "fixture-history-\(index)",
                    sessionID: session.id,
                    role: role,
                    createdAt: .now.addingTimeInterval(Double(-900 + index * 30)),
                    completedAt: .now.addingTimeInterval(Double(-895 + index * 30)),
                    providerID: "openai",
                    modelID: "gpt-5.6-sol",
                    errorMessage: nil,
                    parts: [
                        .text(
                            id: "fixture-history-text-\(index)",
                            text: text,
                            synthetic: false
                        )
                    ]
                )
            }
            return earlierMessages + [
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

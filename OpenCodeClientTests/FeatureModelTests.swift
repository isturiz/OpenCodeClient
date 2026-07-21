import Foundation
import Testing

@testable import OpenCodeClient

private enum StubClientError: Error {
    case rejected
}

private struct PromptCall: Equatable, Sendable {
    let sessionID: String
    let directory: String
    let text: String
    let model: ModelOption?
    let agent: AgentOption?
}

private actor StubOpenCodeClient: OpenCodeClientProtocol {
    var projectValues: [OpenCodeProject]
    var sessionValues: [String: [OpenCodeSession]]
    var statusValues: [String: [String: OpenCodeSessionStatus]]
    var messageValues: [ChatMessage]
    var modelValues: [ModelOption]
    var agentValues: [AgentOption]
    var shouldRejectPrompt = false
    private(set) var promptCalls: [PromptCall] = []

    init(
        projects: [OpenCodeProject] = [],
        sessions: [String: [OpenCodeSession]] = [:],
        statuses: [String: [String: OpenCodeSessionStatus]] = [:],
        messages: [ChatMessage] = [],
        models: [ModelOption] = [],
        agents: [AgentOption] = []
    ) {
        projectValues = projects
        sessionValues = sessions
        statusValues = statuses
        messageValues = messages
        modelValues = models
        agentValues = agents
    }

    func health() -> OpenCodeHealth {
        OpenCodeHealth(isHealthy: true, version: "1.18.3")
    }

    func projects() -> [OpenCodeProject] {
        projectValues
    }

    func sessions(directory: String) -> [OpenCodeSession] {
        sessionValues[directory] ?? []
    }

    func sessionStatuses(directory: String) -> [String: OpenCodeSessionStatus] {
        statusValues[directory] ?? [:]
    }

    func createSession(directory: String, title: String?) throws -> OpenCodeSession {
        guard let session = sessionValues[directory]?.first else {
            throw StubClientError.rejected
        }
        return session
    }

    func messages(sessionID: String, directory: String, limit: Int?) -> [ChatMessage] {
        messageValues
    }

    func promptAsync(
        sessionID: String,
        directory: String,
        text: String,
        model: ModelOption?,
        agent: AgentOption?
    ) throws {
        if shouldRejectPrompt {
            throw StubClientError.rejected
        }
        promptCalls.append(
            PromptCall(
                sessionID: sessionID,
                directory: directory,
                text: text,
                model: model,
                agent: agent
            )
        )
    }

    func abort(sessionID: String, directory: String) {}

    func models(directory: String) -> [ModelOption] {
        modelValues
    }

    func agents(directory: String) -> [AgentOption] {
        agentValues
    }

    func reply(to permission: PermissionRequest, response: PermissionResponse, directory: String) {}

    func events() -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func rejectPrompts() {
        shouldRejectPrompt = true
    }
}

struct FeatureModelTests {
    @Test @MainActor func projectsLoadByDirectoryAndSortByName() async {
        let alpha = OpenCodeProject(id: "alpha", worktree: "/tmp/Alpha", vcs: "git")
        let zebra = OpenCodeProject(id: "zebra", worktree: "/tmp/Zebra", vcs: "git")
        let alphaSession = makeSession(id: "ses_alpha", project: alpha, title: "Alpha work")
        let zebraSession = makeSession(id: "ses_zebra", project: zebra, title: "Zebra work")
        let client = StubOpenCodeClient(
            projects: [zebra, alpha],
            sessions: [alpha.worktree: [alphaSession], zebra.worktree: [zebraSession]],
            statuses: [
                alpha.worktree: [alphaSession.id: .busy],
                zebra.worktree: [zebraSession.id: .idle],
            ]
        )
        let model = ProjectsViewModel()
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")

        await model.connect(profile: profile, client: client)

        #expect(model.phase == .loaded)
        #expect(model.sections.map(\.project.name) == ["Alpha", "Zebra"])
        #expect(model.statuses[alphaSession.id] == .busy)
        model.searchText = "Zebra"
        #expect(model.filteredSections.map(\.project.id) == [zebra.id])
    }

    @Test @MainActor func chatSendUsesSelectedDefaultsAndAddsOptimisticMessage() async throws {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_1", project: project, title: "Build app")
        let modelOption = ModelOption(
            providerID: "openai",
            modelID: "gpt-5.6-sol",
            providerName: "OpenAI",
            name: "GPT-5.6 Sol",
            isConnected: true
        )
        let agent = AgentOption(
            name: "build",
            description: nil,
            mode: "primary",
            isBuiltIn: true
        )
        let client = StubOpenCodeClient(models: [modelOption], agents: [agent])
        let model = ChatViewModel()
        let route = SessionRoute(
            profileID: UUID(),
            project: project,
            session: session
        )

        await model.configure(
            route: route,
            client: client,
            voiceClient: nil,
            usesVoicePostProcessing: false
        )
        model.draft = "  Ship it  "
        await model.send()
        model.suspend()

        let calls = await client.promptCalls
        let call = try #require(calls.first)
        #expect(call.sessionID == session.id)
        #expect(call.directory == project.worktree)
        #expect(call.text == "Ship it")
        #expect(call.model == modelOption)
        #expect(call.agent == agent)
        #expect(model.draft.isEmpty)
        #expect(model.status == .busy)
        #expect(model.messages.last?.role == .user)
        #expect(model.messages.last?.parts.first?.plainText == "Ship it")
    }

    @Test @MainActor func failedChatSendRestoresDraftAndRemovesOptimisticMessage() async {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_1", project: project, title: "Build app")
        let client = StubOpenCodeClient()
        await client.rejectPrompts()
        let model = ChatViewModel()
        let route = SessionRoute(profileID: UUID(), project: project, session: session)

        await model.configure(
            route: route,
            client: client,
            voiceClient: nil,
            usesVoicePostProcessing: false
        )
        model.draft = "Try again"
        await model.send()
        model.suspend()

        #expect(model.draft == "Try again")
        #expect(model.messages.isEmpty)
        #expect(model.presentedError != nil)
        #expect(model.status == .idle)
    }
}

private func makeSession(id: String, project: OpenCodeProject, title: String) -> OpenCodeSession {
    OpenCodeSession(
        id: id,
        projectID: project.id,
        directory: project.worktree,
        parentID: nil,
        title: title,
        version: "1.18.3",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        summary: nil
    )
}

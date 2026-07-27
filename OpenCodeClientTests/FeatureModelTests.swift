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

private struct CreateSessionCall: Equatable, Sendable {
    let directory: String
    let title: String?
}

@MainActor
private final class ClientBox {
    var client: any OpenCodeClientProtocol

    init(client: any OpenCodeClientProtocol) {
        self.client = client
    }
}

private actor StubOpenCodeClient: OpenCodeClientProtocol {
    var projectValues: [OpenCodeProject]
    var sessionValues: [String: [OpenCodeSession]]
    var statusValues: [String: [String: OpenCodeSessionStatus]]
    var messageValues: [ChatMessage]
    var modelValues: [ModelOption]
    var agentValues: [AgentOption]
    var shouldRejectPrompt = false
    var createFailure: NetworkError?
    var promptFailure: NetworkError?
    private(set) var createSessionCalls: [CreateSessionCall] = []
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
        createSessionCalls.append(CreateSessionCall(directory: directory, title: title))
        if let createFailure { throw createFailure }
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
        if let promptFailure { throw promptFailure }
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

    func acceptPrompts() {
        shouldRejectPrompt = false
    }

    func failCreation(with error: NetworkError) {
        createFailure = error
    }

    func failPrompts(with error: NetworkError) {
        promptFailure = error
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

    @Test @MainActor func projectsOrganizeByRecentActivityBuckets() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startOfToday = calendar.startOfDay(for: now)
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let today = makeSession(
            id: "today",
            project: project,
            title: "Today",
            updatedAt: startOfToday.addingTimeInterval(60)
        )
        let yesterday = makeSession(
            id: "yesterday",
            project: project,
            title: "Yesterday",
            updatedAt: startOfToday.addingTimeInterval(-60)
        )
        let previousWeek = makeSession(
            id: "week",
            project: project,
            title: "This week",
            updatedAt: startOfToday.addingTimeInterval(-3 * 86_400)
        )
        let earlier = makeSession(
            id: "earlier",
            project: project,
            title: "Earlier",
            updatedAt: now.addingTimeInterval(-10 * 86_400)
        )
        let client = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [earlier, previousWeek, yesterday, today]]
        )
        let model = ProjectsViewModel(calendar: calendar, now: { now })

        await model.connect(
            profile: ServerProfile(name: "Test", baseURL: "https://example.com"),
            client: client
        )
        model.organization = .projectThenChronology

        let projectSection = try #require(model.projectChronologySections.first)
        #expect(
            projectSection.chronology.map(\.bucket)
                == [.today, .yesterday, .previousSevenDays, .earlier]
        )
        #expect(projectSection.chronology.first?.items.map(\.session.id) == [today.id])
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

    @Test @MainActor func newChatCreatesSessionOnlyWhenFirstMessageIsSent() async throws {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_new", project: project, title: "New chat")
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")
        let client = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [session]]
        )
        let model = ChatViewModel()
        var materializedRoute: SessionRoute?

        await model.configureNewChat(
            profiles: [profile],
            initialProfileID: profile.id,
            initialProject: project,
            clientProvider: { _ in client },
            voiceClient: nil,
            usesVoicePostProcessing: false,
            sessionRouteChanged: { materializedRoute = $0 }
        )

        #expect(await client.createSessionCalls.isEmpty)
        #expect(model.route == nil)

        model.draft = "First prompt"
        await model.send()
        model.suspend()

        let createCalls = await client.createSessionCalls
        let promptCalls = await client.promptCalls
        #expect(createCalls == [CreateSessionCall(directory: project.worktree, title: nil)])
        #expect(promptCalls.first?.sessionID == session.id)
        #expect(promptCalls.first?.text == "First prompt")
        #expect(model.route?.session.id == session.id)
        #expect(materializedRoute?.session.id == session.id)
    }

    @Test @MainActor func promptFailureAfterCreationKeepsSessionForRetry() async throws {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_new", project: project, title: "New chat")
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")
        let client = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [session]]
        )
        await client.rejectPrompts()
        let model = ChatViewModel()

        await model.configureNewChat(
            profiles: [profile],
            initialProfileID: profile.id,
            initialProject: project,
            clientProvider: { _ in client },
            voiceClient: nil,
            usesVoicePostProcessing: false,
            sessionRouteChanged: { _ in }
        )
        model.draft = "Retry me"
        await model.send()

        #expect(model.route?.session.id == session.id)
        #expect(model.draft == "Retry me")
        #expect(await client.createSessionCalls.count == 1)

        await client.acceptPrompts()
        await model.send()
        model.suspend()

        #expect(await client.createSessionCalls.count == 1)
        #expect(await client.promptCalls.count == 1)
    }

    @Test @MainActor func reconfiguringExistingChatReplacesItsClient() async {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_1", project: project, title: "Chat")
        let firstClient = StubOpenCodeClient()
        let secondClient = StubOpenCodeClient()
        let model = ChatViewModel()
        let route = SessionRoute(profileID: UUID(), project: project, session: session)

        await model.configure(
            route: route,
            client: firstClient,
            voiceClient: nil,
            usesVoicePostProcessing: false
        )
        await model.reconfigureClient(secondClient)
        model.draft = "Use the new client"
        await model.send()
        model.suspend()

        #expect(await firstClient.promptCalls.isEmpty)
        #expect(await secondClient.promptCalls.count == 1)
    }

    @Test @MainActor func ambiguousCreateFailurePreventsDuplicateRetry() async {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")
        let client = StubOpenCodeClient(projects: [project])
        await client.failCreation(with: .timedOut)
        let model = ChatViewModel()

        await model.configureNewChat(
            profiles: [profile],
            initialProfileID: profile.id,
            initialProject: project,
            clientProvider: { _ in client },
            voiceClient: nil,
            usesVoicePostProcessing: false,
            sessionRouteChanged: { _ in }
        )
        model.draft = "Do not duplicate"
        await model.send()

        #expect(model.route == nil)
        #expect(model.submissionOutcomeUncertain)
        #expect(!model.canSend)
        #expect(model.draft == "Do not duplicate")
        #expect(await client.createSessionCalls.count == 1)
    }

    @Test @MainActor func ambiguousPromptFailureKeepsCreatedSessionButBlocksResend() async {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_new", project: project, title: "New chat")
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")
        let client = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [session]]
        )
        await client.failPrompts(with: .timedOut)
        let model = ChatViewModel()

        await model.configureNewChat(
            profiles: [profile],
            initialProfileID: profile.id,
            initialProject: project,
            clientProvider: { _ in client },
            voiceClient: nil,
            usesVoicePostProcessing: false,
            sessionRouteChanged: { _ in }
        )
        model.draft = "Maybe accepted"
        await model.send()
        model.suspend()

        #expect(model.route?.session.id == session.id)
        #expect(model.submissionOutcomeUncertain)
        #expect(!model.canSend)
        #expect(await client.createSessionCalls.count == 1)
    }

    @Test @MainActor func refreshingDraftConfigurationReplacesPasswordOnlyClient() async {
        let project = OpenCodeProject(id: "project", worktree: "/tmp/Project", vcs: "git")
        let session = makeSession(id: "ses_new", project: project, title: "New chat")
        let profile = ServerProfile(name: "Test", baseURL: "https://example.com")
        let firstClient = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [session]]
        )
        let secondClient = StubOpenCodeClient(
            projects: [project],
            sessions: [project.worktree: [session]]
        )
        let clientBox = ClientBox(client: firstClient)
        let model = ChatViewModel()

        await model.configureNewChat(
            profiles: [profile],
            initialProfileID: profile.id,
            initialProject: project,
            clientProvider: { _ in clientBox.client },
            voiceClient: nil,
            usesVoicePostProcessing: false,
            sessionRouteChanged: { _ in }
        )
        clientBox.client = secondClient
        await model.refreshDraftConfiguration([profile])
        model.draft = "Use refreshed credentials"
        await model.send()
        model.suspend()

        #expect(await firstClient.createSessionCalls.isEmpty)
        #expect(await secondClient.createSessionCalls.count == 1)
    }
}

private func makeSession(
    id: String,
    project: OpenCodeProject,
    title: String,
    updatedAt: Date = Date(timeIntervalSince1970: 2)
) -> OpenCodeSession {
    OpenCodeSession(
        id: id,
        projectID: project.id,
        directory: project.worktree,
        parentID: nil,
        title: title,
        version: "1.18.3",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: updatedAt,
        summary: nil
    )
}

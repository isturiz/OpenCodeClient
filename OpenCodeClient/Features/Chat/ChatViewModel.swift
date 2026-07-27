import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var route: SessionRoute?
    private(set) var messages: [ChatMessage] = []
    private(set) var permissions: [PermissionRequest] = []
    private(set) var status: OpenCodeSessionStatus = .idle
    private(set) var models: [ModelOption] = []
    private(set) var agents: [AgentOption] = []
    private(set) var availableProfiles: [ServerProfile] = []
    private(set) var availableProjects: [OpenCodeProject] = []
    private(set) var selectedProfileID: UUID?
    private(set) var selectedProject: OpenCodeProject?
    private(set) var isLoadingProjects = false
    private(set) var isCreatingSession = false
    private(set) var isSending = false
    private(set) var isTranscribing = false
    private(set) var eventsConnected = false
    private(set) var submissionOutcomeUncertain = false
    private(set) var isDeleted = false
    var selectedModel: ModelOption?
    var selectedAgent: AgentOption?
    var draft = ""
    var presentedError: String?
    var targetError: String?

    let recorder = VoiceRecorder()

    @ObservationIgnored private var client: (any OpenCodeClientProtocol)?
    @ObservationIgnored private var voiceClient: (any FluidVoiceClientProtocol)?
    @ObservationIgnored private var usesVoicePostProcessing = false
    @ObservationIgnored private var clientProvider:
        ((ServerProfile) async throws -> any OpenCodeClientProtocol)?
    @ObservationIgnored private var sessionRouteChanged: ((SessionRoute) -> Void)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var messageRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var targetGeneration = UUID()
    @ObservationIgnored private var eventGeneration = UUID()
    @ObservationIgnored private var submissionGeneration = UUID()

    var isNewChat: Bool {
        route == nil
    }

    var selectedProfile: ServerProfile? {
        guard let selectedProfileID else { return nil }
        return availableProfiles.first { $0.id == selectedProfileID }
    }

    var canChangeTarget: Bool {
        isNewChat && !isCreatingSession && !isSending
    }

    var canSend: Bool {
        let hasTarget = route != nil || (selectedProfileID != nil && selectedProject != nil && client != nil)
        return hasTarget && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending && !isTranscribing && recorder.state != .recording
            && !submissionOutcomeUncertain && !isDeleted
    }

    func configure(
        route: SessionRoute,
        client: any OpenCodeClientProtocol,
        voiceClient: (any FluidVoiceClientProtocol)?,
        usesVoicePostProcessing: Bool,
        sessionRouteChanged: ((SessionRoute) -> Void)? = nil
    ) async {
        let changed = self.route?.id != route.id
        self.route = route
        self.client = client
        self.voiceClient = voiceClient
        self.usesVoicePostProcessing = usesVoicePostProcessing
        self.sessionRouteChanged = sessionRouteChanged
        availableProfiles = []
        availableProjects = []
        selectedProfileID = route.profileID
        selectedProject = route.project
        clientProvider = nil
        if changed {
            resetConversationState(clearDraft: false)
        }
        await load()
        guard !Task.isCancelled else { return }
        startEvents()
    }

    func configureNewChat(
        profiles: [ServerProfile],
        initialProfileID: UUID?,
        initialProject: OpenCodeProject?,
        clientProvider: @escaping (ServerProfile) async throws -> any OpenCodeClientProtocol,
        voiceClient: (any FluidVoiceClientProtocol)?,
        usesVoicePostProcessing: Bool,
        sessionRouteChanged: @escaping (SessionRoute) -> Void
    ) async {
        generation = UUID()
        resetConversationState(clearDraft: false)
        route = nil
        phase = .loaded
        availableProfiles = profiles
        self.clientProvider = clientProvider
        self.voiceClient = voiceClient
        self.usesVoicePostProcessing = usesVoicePostProcessing
        self.sessionRouteChanged = sessionRouteChanged

        let preferredProfileID =
            initialProfileID.flatMap { id in profiles.contains(where: { $0.id == id }) ? id : nil }
            ?? profiles.first?.id
        guard let preferredProfileID else {
            targetError = String(localized: "Add an OpenCode server before starting a chat.")
            return
        }
        await selectProfile(id: preferredProfileID, preferredProject: initialProject)
    }

    func refreshDraftConfiguration(_ profiles: [ServerProfile]) async {
        guard isNewChat else { return }
        while isSending {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
        guard isNewChat, !Task.isCancelled else { return }
        let previousProject = selectedProject
        availableProfiles = profiles
        let profileID =
            selectedProfileID.flatMap { selectedID in
                profiles.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? profiles.first?.id
        guard let profileID else {
            selectedProfileID = nil
            selectedProject = nil
            availableProjects = []
            client = nil
            targetError = String(localized: "Add an OpenCode server before starting a chat.")
            return
        }
        await selectProfile(id: profileID, preferredProject: previousProject, force: true)
    }

    func configureVoice(
        client: (any FluidVoiceClientProtocol)?,
        usesPostProcessing: Bool
    ) {
        cancelVoiceWork()
        voiceClient = client
        usesVoicePostProcessing = usesPostProcessing
    }

    func reconfigureClient(_ client: any OpenCodeClientProtocol) async {
        guard route != nil else { return }
        while isSending {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        generation = UUID()
        eventGeneration = UUID()
        eventTask?.cancel()
        eventTask = nil
        messageRefreshTask?.cancel()
        messageRefreshTask = nil
        eventsConnected = false
        self.client = client
        await load()
        guard !Task.isCancelled else { return }
        startEvents()
    }

    func selectProfile(id: UUID) async {
        await selectProfile(id: id, preferredProject: nil)
    }

    func selectProject(id: String) async {
        guard canChangeTarget, let project = availableProjects.first(where: { $0.id == id }) else {
            return
        }
        selectedProject = project
        await loadOptions(for: project)
    }

    func load() async {
        guard let route, let client else { return }
        let requestedGeneration = generation
        phase = .loading

        do {
            async let messagesRequest = client.messages(
                sessionID: route.session.id,
                directory: route.project.worktree,
                limit: 200
            )
            async let statusesRequest = client.sessionStatuses(directory: route.project.worktree)
            let (messages, statuses) = try await (messagesRequest, statusesRequest)
            guard generation == requestedGeneration else { return }
            self.messages = messages
            status = statuses[route.session.id] ?? .idle
            phase = .loaded

            await loadOptions(for: route.project, expectedGeneration: requestedGeneration)
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error == .cancelled {
            return
        } catch {
            guard generation == requestedGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func refreshMessages() async {
        guard let route, let client else { return }
        do {
            let loaded = try await client.messages(
                sessionID: route.session.id,
                directory: route.project.worktree,
                limit: 200
            )
            let pending = messages.filter { $0.id.hasPrefix("temporary-user-") }
            let loadedTexts = Set(
                loaded.filter { $0.role == .user }.compactMap { message in
                    message.parts.compactMap(\.plainText).joined(separator: "\n").normalizedForComparison
                }
            )
            messages =
                loaded
                + pending.filter { message in
                    let text = message.parts.compactMap(\.plainText).joined(separator: "\n")
                        .normalizedForComparison
                    return !loadedTexts.contains(text)
                }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func send() async {
        guard canSend, let client else { return }
        let submissionID = UUID()
        submissionGeneration = submissionID
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedModel = selectedModel
        let submittedAgent = selectedAgent
        let submittedProject = route?.project ?? selectedProject
        guard let submittedProject else { return }

        draft = ""
        isSending = true
        defer {
            isCreatingSession = false
            isSending = false
        }

        var destinationRoute = route
        if destinationRoute == nil {
            guard let selectedProfileID else {
                restoreDraft(text)
                return
            }
            isCreatingSession = true
            do {
                let session = try await client.createSession(
                    directory: submittedProject.worktree,
                    title: nil
                )
                guard submissionGeneration == submissionID, !Task.isCancelled else { return }
                let createdRoute = SessionRoute(
                    profileID: selectedProfileID,
                    project: submittedProject,
                    session: session
                )
                route = createdRoute
                destinationRoute = createdRoute
                isCreatingSession = false
                sessionRouteChanged?(createdRoute)
                startEvents()
            } catch {
                guard submissionGeneration == submissionID, !Task.isCancelled else { return }
                restoreDraft(text)
                if Self.hasAmbiguousOutcome(error) {
                    submissionOutcomeUncertain = true
                    presentedError = String(
                        localized:
                            "The server may have created this conversation. Return to Projects and refresh before trying again."
                    )
                } else {
                    presentedError = error.localizedDescription
                }
                return
            }
        }

        guard let destinationRoute else {
            restoreDraft(text)
            return
        }
        let temporaryID = "temporary-user-\(UUID().uuidString)"
        messages.append(
            ChatMessage(
                id: temporaryID,
                sessionID: destinationRoute.session.id,
                role: .user,
                createdAt: .now,
                completedAt: .now,
                providerID: submittedModel?.providerID,
                modelID: submittedModel?.modelID,
                errorMessage: nil,
                parts: [.text(id: "\(temporaryID)-text", text: text, synthetic: false)]
            )
        )

        let submittedAt = Date.now
        do {
            try await client.promptAsync(
                sessionID: destinationRoute.session.id,
                directory: destinationRoute.project.worktree,
                text: text,
                model: submittedModel,
                agent: submittedAgent
            )
            guard submissionGeneration == submissionID, !Task.isCancelled else { return }
            status = .busy
        } catch {
            guard submissionGeneration == submissionID, !Task.isCancelled else { return }
            if Self.hasAmbiguousOutcome(error) {
                await refreshMessages()
                let wasAccepted = messages.contains { message in
                    message.role == .user && !message.id.hasPrefix("temporary-user-")
                        && message.createdAt >= submittedAt.addingTimeInterval(-1)
                        && message.parts.compactMap(\.plainText).joined(separator: "\n")
                            .normalizedForComparison == text.normalizedForComparison
                }
                if wasAccepted {
                    status = .busy
                    return
                }
                submissionOutcomeUncertain = true
                presentedError = String(
                    localized:
                        "The message may have been accepted by the server. Return to Projects and refresh before sending it again."
                )
            } else {
                presentedError = error.localizedDescription
            }
            messages.removeAll { $0.id == temporaryID }
            restoreDraft(text)
        }
    }

    func abort() async {
        guard let route, let client else { return }
        do {
            try await client.abort(sessionID: route.session.id, directory: route.project.worktree)
            status = .idle
            await refreshMessages()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func respond(to permission: PermissionRequest, with response: PermissionResponse) async {
        guard let route, let client else { return }
        do {
            try await client.reply(to: permission, response: response, directory: route.project.worktree)
            permissions.removeAll { $0.id == permission.id }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func toggleVoiceRecording() async {
        if recorder.state == .recording {
            do {
                let fileURL = try recorder.stop()
                beginTranscription(fileURL: fileURL)
            } catch {
                presentedError = error.localizedDescription
            }
            return
        }

        guard voiceClient != nil else {
            presentedError = String(localized: "Configure a Voice server in Settings before dictating.")
            return
        }

        do {
            try await recorder.start()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func cancelVoiceWork() {
        if recorder.state == .recording {
            recorder.cancel()
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
    }

    func suspend() {
        eventGeneration = UUID()
        eventTask?.cancel()
        eventTask = nil
        eventsConnected = false
        cancelVoiceWork()
    }

    func resume() async {
        guard route != nil else { return }
        await refreshMessages()
        startEvents()
    }

    private func selectProfile(
        id: UUID,
        preferredProject: OpenCodeProject?,
        force: Bool = false
    ) async {
        guard isNewChat, (force || canChangeTarget),
            let profile = availableProfiles.first(where: { $0.id == id })
        else {
            return
        }
        let requestedGeneration = UUID()
        targetGeneration = requestedGeneration
        selectedProfileID = profile.id
        selectedProject = nil
        availableProjects = []
        models = []
        agents = []
        selectedModel = nil
        selectedAgent = nil
        targetError = nil
        client = nil
        isLoadingProjects = true
        defer {
            if targetGeneration == requestedGeneration {
                isLoadingProjects = false
            }
        }

        do {
            guard let clientProvider else { throw NetworkError.invalidResponse }
            let loadedClient = try await clientProvider(profile)
            let projects = try await loadedClient.projects()
            guard targetGeneration == requestedGeneration, selectedProfileID == profile.id else {
                return
            }
            client = loadedClient
            availableProjects = projects.sorted(by: Self.projectOrder)

            if let preferredProject,
                let project = availableProjects.first(where: {
                    $0.id == preferredProject.id || $0.worktree == preferredProject.worktree
                })
            {
                selectedProject = project
                isLoadingProjects = false
                await loadOptions(for: project)
            }
        } catch {
            guard targetGeneration == requestedGeneration else { return }
            targetError = error.localizedDescription
        }
    }

    private func loadOptions(
        for project: OpenCodeProject,
        expectedGeneration: UUID? = nil
    ) async {
        guard let client else { return }
        let requestedGeneration = expectedGeneration ?? UUID()
        if expectedGeneration == nil {
            targetGeneration = requestedGeneration
        }
        models = []
        agents = []
        selectedModel = nil
        selectedAgent = nil

        async let modelRequest = try? client.models(directory: project.worktree)
        async let agentRequest = try? client.agents(directory: project.worktree)
        let (models, agents) = await (modelRequest ?? [], agentRequest ?? [])
        if let expectedGeneration {
            guard generation == expectedGeneration else { return }
        } else {
            guard targetGeneration == requestedGeneration, selectedProject?.id == project.id else {
                return
            }
        }
        self.models = models
        self.agents = agents
        selectedModel = models.first(where: \.isConnected)
        selectedAgent = agents.first(where: { $0.name == "build" }) ?? agents.first
    }

    private func resetConversationState(clearDraft: Bool) {
        generation = UUID()
        targetGeneration = UUID()
        eventGeneration = UUID()
        submissionGeneration = UUID()
        eventTask?.cancel()
        eventTask = nil
        messageRefreshTask?.cancel()
        messageRefreshTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recorder.cancel()
        messages = []
        permissions = []
        models = []
        agents = []
        selectedModel = nil
        selectedAgent = nil
        status = .idle
        eventsConnected = false
        isCreatingSession = false
        isSending = false
        isTranscribing = false
        submissionOutcomeUncertain = false
        isDeleted = false
        presentedError = nil
        targetError = nil
        if clearDraft {
            draft = ""
        }
    }

    private func restoreDraft(_ submittedText: String) {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = submittedText
        } else {
            draft = "\(submittedText)\n\(draft)"
        }
    }

    private func beginTranscription(fileURL: URL) {
        guard let voiceClient else {
            recorder.remove(fileURL: fileURL)
            return
        }
        transcriptionTask?.cancel()
        isTranscribing = true
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.recorder.remove(fileURL: fileURL)
                self.isTranscribing = false
                self.transcriptionTask = nil
            }
            do {
                let transcript = try await voiceClient.transcribe(
                    fileURL: fileURL,
                    postprocess: self.usesVoicePostProcessing
                )
                try Task.checkCancellation()
                self.appendTranscript(transcript)
            } catch is CancellationError {
                return
            } catch let error as NetworkError where error == .cancelled {
                return
            } catch {
                self.presentedError = error.localizedDescription
            }
        }
    }

    private func appendTranscript(_ transcript: String) {
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = value
        } else {
            draft += draft.hasSuffix(" ") ? value : " \(value)"
        }
    }

    private func startEvents() {
        guard route != nil, eventTask == nil, client != nil else { return }
        let requestedGeneration = UUID()
        eventGeneration = requestedGeneration
        eventTask = Task { [weak self] in
            await self?.consumeEvents(generation: requestedGeneration)
        }
    }

    private func consumeEvents(generation requestedGeneration: UUID) async {
        var attempt = 0
        while !Task.isCancelled, eventGeneration == requestedGeneration {
            guard let client else { return }
            do {
                let stream = try await client.events()
                guard eventGeneration == requestedGeneration else { return }
                eventsConnected = true
                if attempt > 0 {
                    await refreshMessages()
                    await refreshStatus()
                }
                attempt = 0
                for try await event in stream {
                    try Task.checkCancellation()
                    guard eventGeneration == requestedGeneration else { return }
                    handle(event)
                }
                if eventGeneration == requestedGeneration {
                    eventsConnected = false
                }
            } catch is CancellationError {
                break
            } catch {
                guard eventGeneration == requestedGeneration else { return }
                eventsConnected = false
                attempt += 1
                let delay = min(pow(2, Double(attempt)), 30) + Double.random(in: 0...0.4)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        if eventGeneration == requestedGeneration {
            eventsConnected = false
            eventTask = nil
        }
    }

    private func handle(_ globalEvent: OpenCodeGlobalEvent) {
        guard let route else { return }
        if let directory = globalEvent.directory, !sameDirectory(directory, route.project.worktree) {
            return
        }

        switch globalEvent.event {
        case .connected:
            scheduleMessageRefresh()
            Task { [weak self] in await self?.refreshStatus() }
        case let .sessionUpdated(session) where session.id == route.session.id:
            let updatedRoute = SessionRoute(
                profileID: route.profileID,
                project: route.project,
                session: session
            )
            self.route = updatedRoute
            sessionRouteChanged?(updatedRoute)
        case let .sessionDeleted(session) where session.id == route.session.id:
            isDeleted = true
            presentedError = String(localized: "This conversation was deleted on the server.")
        case let .sessionStatus(sessionID, status) where sessionID == route.session.id:
            self.status = status
        case let .sessionIdle(sessionID) where sessionID == route.session.id:
            status = .idle
            scheduleMessageRefresh()
        case let .messageChanged(sessionID) where sessionID == route.session.id:
            scheduleMessageRefresh()
        case let .partUpdated(sessionID, messageID, part, delta) where sessionID == route.session.id:
            applyPartUpdate(messageID: messageID, part: part, delta: delta)
        case let .partRemoved(sessionID, messageID, partID) where sessionID == route.session.id:
            guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].parts.removeAll { $0.id == partID }
        case let .permissionUpdated(permission) where permission.sessionID == route.session.id:
            permissions.removeAll { $0.id == permission.id }
            permissions.append(permission)
        case let .permissionReplied(sessionID, permissionID) where sessionID == route.session.id:
            permissions.removeAll { $0.id == permissionID }
        case let .sessionError(sessionID, message) where sessionID == nil || sessionID == route.session.id:
            presentedError = message ?? String(localized: "OpenCode reported a session error.")
        default:
            break
        }
    }

    private func applyPartUpdate(messageID: String, part: MessagePart, delta: String?) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            scheduleMessageRefresh()
            return
        }

        if let partIndex = messages[messageIndex].parts.firstIndex(where: { $0.id == part.id }) {
            if let delta, let existing = messages[messageIndex].parts[partIndex].plainText,
                part.plainText?.isEmpty != false
            {
                switch part {
                case let .text(id, _, synthetic):
                    messages[messageIndex].parts[partIndex] = .text(
                        id: id,
                        text: existing + delta,
                        synthetic: synthetic
                    )
                case let .reasoning(id, _):
                    messages[messageIndex].parts[partIndex] = .reasoning(id: id, text: existing + delta)
                default:
                    messages[messageIndex].parts[partIndex] = part
                }
            } else {
                messages[messageIndex].parts[partIndex] = part
            }
        } else {
            messages[messageIndex].parts.append(part)
        }
    }

    private func scheduleMessageRefresh() {
        messageRefreshTask?.cancel()
        messageRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.refreshMessages()
            self?.messageRefreshTask = nil
        }
    }

    private func refreshStatus() async {
        guard let route, let client else { return }
        do {
            let statuses = try await client.sessionStatuses(directory: route.project.worktree)
            status = statuses[route.session.id] ?? .idle
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error == .cancelled {
            return
        } catch {
            // Message reconciliation remains useful even if status refresh temporarily fails.
        }
    }

    private func sameDirectory(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path
            == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static func projectOrder(_ lhs: OpenCodeProject, _ rhs: OpenCodeProject) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.worktree.localizedStandardCompare(rhs.worktree) == .orderedAscending
    }

    private static func hasAmbiguousOutcome(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        switch networkError {
        case .invalidURL, .insecureRemoteURL:
            return false
        case let .httpStatus(status, _):
            return status >= 500 || status == 408
        case .invalidResponse, .decoding, .timedOut, .cancelled, .unreachable:
            return true
        }
    }
}

private extension String {
    var normalizedForComparison: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

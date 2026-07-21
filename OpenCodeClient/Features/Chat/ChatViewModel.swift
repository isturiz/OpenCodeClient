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
    private(set) var isSending = false
    private(set) var isTranscribing = false
    private(set) var eventsConnected = false
    var selectedModel: ModelOption?
    var selectedAgent: AgentOption?
    var draft = ""
    var presentedError: String?

    let recorder = VoiceRecorder()

    @ObservationIgnored private var client: (any OpenCodeClientProtocol)?
    @ObservationIgnored private var voiceClient: (any FluidVoiceClientProtocol)?
    @ObservationIgnored private var usesVoicePostProcessing = false
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var messageRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    var canSend: Bool {
        route != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var hasVoiceConfiguration: Bool {
        voiceClient != nil
    }

    func configure(
        route: SessionRoute,
        client: any OpenCodeClientProtocol,
        voiceClient: (any FluidVoiceClientProtocol)?,
        usesVoicePostProcessing: Bool
    ) async {
        let changed = self.route?.id != route.id
        self.route = route
        self.client = client
        self.voiceClient = voiceClient
        self.usesVoicePostProcessing = usesVoicePostProcessing
        if changed {
            generation = UUID()
            eventTask?.cancel()
            messageRefreshTask?.cancel()
            transcriptionTask?.cancel()
            recorder.cancel()
            messages = []
            permissions = []
            selectedModel = nil
            selectedAgent = nil
            status = .idle
        }
        await load()
        startEvents()
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

            async let modelRequest = try? client.models(directory: route.project.worktree)
            async let agentRequest = try? client.agents(directory: route.project.worktree)
            let (models, agents) = await (modelRequest ?? [], agentRequest ?? [])
            guard generation == requestedGeneration else { return }
            self.models = models
            self.agents = agents
            if selectedModel == nil {
                selectedModel = models.first(where: \.isConnected)
            }
            if selectedAgent == nil {
                selectedAgent = agents.first(where: { $0.name == "build" }) ?? agents.first
            }
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
        guard canSend, let route, let client else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        isSending = true
        let temporaryID = "temporary-user-\(UUID().uuidString)"
        messages.append(
            ChatMessage(
                id: temporaryID,
                sessionID: route.session.id,
                role: .user,
                createdAt: .now,
                completedAt: .now,
                providerID: selectedModel?.providerID,
                modelID: selectedModel?.modelID,
                errorMessage: nil,
                parts: [.text(id: "\(temporaryID)-text", text: text, synthetic: false)]
            )
        )

        do {
            try await client.promptAsync(
                sessionID: route.session.id,
                directory: route.project.worktree,
                text: text,
                model: selectedModel,
                agent: selectedAgent
            )
            status = .busy
        } catch {
            messages.removeAll { $0.id == temporaryID }
            draft = text
            presentedError = error.localizedDescription
        }
        isSending = false
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
            presentedError = String(localized: "Configure and test FluidVoice in Settings before dictating.")
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
        eventTask?.cancel()
        eventTask = nil
        eventsConnected = false
        cancelVoiceWork()
    }

    func resume() async {
        await refreshMessages()
        startEvents()
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
        guard eventTask == nil, client != nil else { return }
        eventTask = Task { [weak self] in
            await self?.consumeEvents()
        }
    }

    private func consumeEvents() async {
        var attempt = 0
        while !Task.isCancelled {
            guard let client else { return }
            do {
                let stream = try await client.events()
                eventsConnected = true
                if attempt > 0 {
                    await refreshMessages()
                }
                attempt = 0
                for try await event in stream {
                    try Task.checkCancellation()
                    handle(event)
                }
                eventsConnected = false
            } catch is CancellationError {
                break
            } catch {
                eventsConnected = false
                attempt += 1
                let delay = min(pow(2, Double(attempt)), 30) + Double.random(in: 0...0.4)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        eventsConnected = false
        eventTask = nil
    }

    private func handle(_ globalEvent: OpenCodeGlobalEvent) {
        guard let route else { return }
        if let directory = globalEvent.directory, !sameDirectory(directory, route.project.worktree) {
            return
        }

        switch globalEvent.event {
        case .connected:
            scheduleMessageRefresh()
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

    private func sameDirectory(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path
            == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }
}

private extension String {
    var normalizedForComparison: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

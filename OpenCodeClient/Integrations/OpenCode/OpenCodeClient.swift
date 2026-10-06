import Foundation

protocol OpenCodeClientProtocol: Sendable {
    func health() async throws -> OpenCodeHealth
    func projects() async throws -> [OpenCodeProject]
    func sessions(directory: String) async throws -> [OpenCodeSession]
    func session(sessionID: String, directory: String) async throws -> OpenCodeSession
    func permissions(sessionID: String, directory: String) async throws -> [PermissionRequest]
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus]
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession
    func updateSessionTitle(
        sessionID: String,
        directory: String,
        title: String
    ) async throws -> OpenCodeSession
    func sessionDiff(sessionID: String, directory: String) async throws -> [OpenCodeFileDiff]
    func files(directory: String, path: String) async throws -> [OpenCodeFileNode]
    func fileContent(directory: String, path: String) async throws -> OpenCodeFileContent
    func messages(sessionID: String, directory: String, limit: Int?) async throws -> [ChatMessage]
    func promptAsync(
        sessionID: String,
        directory: String,
        text: String,
        model: ModelOption?,
        agent: AgentOption?
    ) async throws
    func abort(sessionID: String, directory: String) async throws
    func models(directory: String) async throws -> [ModelOption]
    func agents(directory: String) async throws -> [AgentOption]
    func reply(
        to permission: PermissionRequest,
        response: PermissionResponse,
        directory: String
    ) async throws
    func events() async throws -> AsyncThrowingStream<OpenCodeGlobalEvent, Error>
}

actor LiveOpenCodeClient: OpenCodeClientProtocol {
    private let baseURL: URL
    private let username: String?
    private let password: String?
    private let session: URLSession
    private let http: HTTPClient
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(configuration: OpenCodeClientConfiguration, session: URLSession = .shared) throws {
        baseURL = try ServerURLPolicy.normalizedURL(from: configuration.profile.baseURL)
        username = configuration.profile.username.nilIfBlank
        password = configuration.password?.nilIfBlank
        self.session = session
        http = HTTPClient(session: session)
    }

    func health() async throws -> OpenCodeHealth {
        let data: Data
        do {
            data = try await send(path: "/api/info")
        } catch NetworkError.httpStatus(404, _) {
            throw NetworkError.unsupportedServerVersion
        }
        let response: HealthDTO = try decode(data)
        return OpenCodeHealth(isHealthy: true, version: response.version)
    }

    func projects() async throws -> [OpenCodeProject] {
        let data = try await send(path: "/api/project")
        let response: [ProjectDTO] = try decode(data)
        return response.map { $0.domain() }
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        var sessions: [OpenCodeSession] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            let query = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            let data = try await send(path: "/api/session", directory: directory, additionalQuery: query)
            let response: PageDTO<SessionDTO> = try decode(data)
            sessions.append(contentsOf: response.data.map { $0.domain() })
            cursor = response.cursor.next
            if let cursor, !seenCursors.insert(cursor).inserted { throw NetworkError.invalidResponse }
        } while cursor != nil
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func session(sessionID: String, directory: String) async throws -> OpenCodeSession {
        let data = try await send(path: "/api/session/\(sessionID)", directory: directory)
        let response: DataResponseDTO<SessionDTO> = try decode(data)
        return response.data.domain()
    }

    func permissions(sessionID: String, directory: String) async throws -> [PermissionRequest] {
        let data = try await send(path: "/api/session/\(sessionID)/permission", directory: directory)
        let response: DataResponseDTO<[PermissionDTO]> = try decode(data)
        return response.data.map { $0.domain() }
    }

    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] {
        let data = try await send(path: "/api/session/active", directory: directory)
        let response: DataResponseDTO<[String: SessionStatusDTO]> = try decode(data)
        return response.data.mapValues { $0.domain() }
    }

    func createSession(directory: String, title: String?) async throws -> OpenCodeSession {
        struct Body: Encodable {
            let title: String?
            let location: LocationDTO
        }

        let body = try encoder.encode(
            Body(title: title?.nilIfBlank, location: LocationDTO(directory: directory)))
        let data = try await send(path: "/api/session", method: "POST", directory: directory, body: body)
        let response: DataResponseDTO<SessionDTO> = try decode(data)
        return response.data.domain()
    }

    func updateSessionTitle(
        sessionID: String,
        directory: String,
        title: String
    ) async throws -> OpenCodeSession {
        let body = try encoder.encode(
            SessionUpdateDTO(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        _ = try await send(
            path: "/api/session/\(sessionID)",
            method: "PATCH",
            directory: directory,
            body: body
        )
        return try await self.session(sessionID: sessionID, directory: directory)
    }

    func sessionDiff(sessionID: String, directory: String) async throws -> [OpenCodeFileDiff] {
        let data = try await send(path: "/api/session/\(sessionID)/diff", directory: directory)
        let response: DataResponseDTO<[FileDiffDTO]> = try decode(data)
        return response.data.map { $0.domain() }
    }

    func files(directory: String, path: String) async throws -> [OpenCodeFileNode] {
        let data = try await send(
            path: "/api/fs/list",
            directory: directory,
            additionalQuery: [URLQueryItem(name: "path", value: path)],
            locationScoped: true
        )
        let response: DataResponseDTO<[FileNodeDTO]> = try decode(data)
        return response.data.map { $0.domain() }
    }

    func fileContent(directory: String, path: String) async throws -> OpenCodeFileContent {
        let data = try await send(
            path: "/api/fs/read/\(path)",
            directory: directory,
            locationScoped: true
        )
        // V2 serves raw bytes rather than a JSON content envelope.
        if !data.contains(0), let text = String(data: data, encoding: .utf8) {
            return OpenCodeFileContent(type: .text, content: text)
        }
        return OpenCodeFileContent(type: .binary, content: nil)
    }

    func messages(sessionID: String, directory: String, limit: Int?) async throws -> [ChatMessage] {
        if let limit, limit <= 0 { return [] }
        var messages: [ChatMessage] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            let pageSize = min(limit.map { $0 - messages.count } ?? 100, 100)
            var query = [URLQueryItem(name: "limit", value: String(pageSize))]
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            } else {
                query.append(URLQueryItem(name: "order", value: "desc"))
            }
            let data = try await send(
                path: "/api/session/\(sessionID)/message", directory: directory, additionalQuery: query
            )
            let response: PageDTO<MessageDTO> = try decode(data)
            messages.append(contentsOf: response.data.map { $0.domain(sessionID: sessionID) })
            cursor = response.cursor.next
            if let cursor, !seenCursors.insert(cursor).inserted { throw NetworkError.invalidResponse }
        } while cursor != nil && (limit.map { messages.count < $0 } ?? true)
        return messages.reversed()
    }

    func promptAsync(
        sessionID: String,
        directory: String,
        text: String,
        model: ModelOption?,
        agent: AgentOption?
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // In V2, model and agent are session state, not fields on a prompt.
        if let model {
            struct Body: Encodable { let model: ModelReferenceDTO }
            _ = try await send(
                path: "/api/session/\(sessionID)/model", method: "POST", directory: directory,
                body: try encoder.encode(
                    Body(
                        model: ModelReferenceDTO(
                            id: model.modelID, providerID: model.providerID, variant: model.variant))
                )
            )
        }
        if let agent {
            struct Body: Encodable { let agent: String }
            _ = try await send(
                path: "/api/session/\(sessionID)/agent", method: "POST", directory: directory,
                body: try encoder.encode(Body(agent: agent.id))
            )
        }
        let body = PromptBodyDTO(id: "msg_\(UUID().uuidString)", text: trimmed)
        let payload = try encoder.encode(body)
        _ = try await send(
            path: "/api/session/\(sessionID)/prompt",
            method: "POST",
            directory: directory,
            body: payload
        )
    }

    func abort(sessionID: String, directory: String) async throws {
        _ = try await send(
            path: "/api/session/\(sessionID)/interrupt", method: "POST", directory: directory,
            additionalQuery: [URLQueryItem(name: "resume", value: "false")]
        )
    }

    func models(directory: String) async throws -> [ModelOption] {
        let data = try await send(path: "/api/model", directory: directory, locationScoped: true)
        let response: DataResponseDTO<[ModelDTO]> = try decode(data)
        return response.data.flatMap { $0.domain() }.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.providerName != $1.providerName { return $0.providerName < $1.providerName }
            return $0.name < $1.name
        }
    }

    func agents(directory: String) async throws -> [AgentOption] {
        let data = try await send(path: "/api/agent", directory: directory, locationScoped: true)
        let response: DataResponseDTO<[AgentDTO]> = try decode(data)
        return
            response.data
            .filter { !$0.hidden && ($0.mode == "primary" || $0.mode == "all") }
            .map { $0.domain() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func reply(
        to permission: PermissionRequest,
        response: PermissionResponse,
        directory: String
    ) async throws {
        struct Body: Encodable {
            let decision: PermissionResponse
        }

        let body = try encoder.encode(Body(decision: response))
        _ = try await send(
            path: "/api/session/\(permission.sessionID)/permission/\(permission.id)/reply",
            method: "POST",
            directory: directory,
            body: body
        )
    }

    func events() throws -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        let request = try makeRequest(path: "/api/event", method: "GET", body: nil, queryItems: [])
        let session = session

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else {
                        throw NetworkError.invalidResponse
                    }
                    guard (200..<300).contains(response.statusCode) else {
                        throw NetworkError.httpStatus(response.statusCode, nil)
                    }

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let data = parser.consume(line: line)
                        guard !parser.didExceedLimit else { throw NetworkError.invalidResponse }
                        guard let data else { continue }
                        guard parser.lastEventName != "effect/httpapi/stream/failure" else {
                            throw NetworkError.invalidResponse
                        }
                        let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: data)
                        if case .dropped = continuation.yield(OpenCodeEventMapper.domain(from: envelope)) {
                            continuation.yield(OpenCodeGlobalEvent(directory: nil, event: .connected))
                        }
                    }
                    if let data = parser.finish() {
                        guard parser.lastEventName != "effect/httpapi/stream/failure" else {
                            throw NetworkError.invalidResponse
                        }
                        let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: data)
                        continuation.yield(OpenCodeEventMapper.domain(from: envelope))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: NetworkError.map(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func send(
        path: String,
        method: String = "GET",
        directory: String? = nil,
        additionalQuery: [URLQueryItem] = [],
        locationScoped: Bool = false,
        body: Data? = nil,
        accepting: Range<Int> = 200..<300
    ) async throws -> Data {
        var query = additionalQuery
        if let directory {
            query.insert(URLQueryItem(name: "directory", value: directory), at: 0)
            if locationScoped {
                query.append(URLQueryItem(name: "location[directory]", value: directory))
            }
        }
        let request = try makeRequest(path: path, method: method, body: body, queryItems: query)
        return try await http.data(for: request, accepting: accepting)
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        let url = try ServerURLPolicy.appending(path: path, to: baseURL, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path == "/api/event" ? 3_600 : 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if path.hasPrefix("/api/fs/read/") {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let password {
            let credential = "\(username ?? "opencode"):\(password)"
            request.setValue(
                "Basic \(Data(credential.utf8).base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }
        if path == "/api/event" {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        return request
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw NetworkError.decoding
        }
    }
}

extension OpenCodeClientProtocol {
    func session(sessionID: String, directory: String) async throws -> OpenCodeSession {
        throw NetworkError.invalidResponse
    }

    func permissions(sessionID: String, directory: String) async throws -> [PermissionRequest] {
        []
    }

    func updateSessionTitle(
        sessionID: String,
        directory: String,
        title: String
    ) async throws -> OpenCodeSession {
        throw NetworkError.invalidResponse
    }

    func sessionDiff(sessionID: String, directory: String) async throws -> [OpenCodeFileDiff] {
        throw NetworkError.invalidResponse
    }

    func files(directory: String, path: String) async throws -> [OpenCodeFileNode] {
        throw NetworkError.invalidResponse
    }

    func fileContent(directory: String, path: String) async throws -> OpenCodeFileContent {
        throw NetworkError.invalidResponse
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

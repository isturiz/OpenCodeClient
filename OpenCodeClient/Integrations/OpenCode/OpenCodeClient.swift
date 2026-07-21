import Foundation

protocol OpenCodeClientProtocol: Sendable {
    func health() async throws -> OpenCodeHealth
    func projects() async throws -> [OpenCodeProject]
    func sessions(directory: String) async throws -> [OpenCodeSession]
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus]
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession
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
        let data = try await send(path: "/global/health")
        let response: HealthDTO = try decode(data)
        return OpenCodeHealth(isHealthy: response.healthy, version: response.version)
    }

    func projects() async throws -> [OpenCodeProject] {
        let data = try await send(path: "/project")
        let response: [ProjectDTO] = try decode(data)
        return response.map { $0.domain() }
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        let data = try await send(path: "/session", directory: directory)
        let response: [SessionDTO] = try decode(data)
        return response.map { $0.domain() }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] {
        let data = try await send(path: "/session/status", directory: directory)
        let response: [String: SessionStatusDTO] = try decode(data)
        return response.mapValues { $0.domain() }
    }

    func createSession(directory: String, title: String?) async throws -> OpenCodeSession {
        struct Body: Encodable {
            let title: String?
        }

        let body = try encoder.encode(Body(title: title?.nilIfBlank))
        let data = try await send(path: "/session", method: "POST", directory: directory, body: body)
        let response: SessionDTO = try decode(data)
        return response.domain()
    }

    func messages(sessionID: String, directory: String, limit: Int?) async throws -> [ChatMessage] {
        var query: [URLQueryItem] = []
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let data = try await send(
            path: "/session/\(sessionID)/message",
            directory: directory,
            additionalQuery: query
        )
        guard !data.isEmpty else { return [] }
        let response: [MessageEnvelopeDTO] = try decode(data)
        return response.map { $0.domain() }
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
        let body = PromptBodyDTO(
            model: model.map { .init(providerID: $0.providerID, modelID: $0.modelID) },
            agent: agent?.name,
            parts: [.init(text: trimmed)]
        )
        let payload = try encoder.encode(body)
        _ = try await send(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            directory: directory,
            body: payload,
            accepting: 200..<205
        )
    }

    func abort(sessionID: String, directory: String) async throws {
        _ = try await send(path: "/session/\(sessionID)/abort", method: "POST", directory: directory)
    }

    func models(directory: String) async throws -> [ModelOption] {
        let data = try await send(path: "/provider", directory: directory)
        let response: ProviderResponseDTO = try decode(data)
        return response.domain()
    }

    func agents(directory: String) async throws -> [AgentOption] {
        let data = try await send(path: "/agent", directory: directory)
        let response: [AgentDTO] = try decode(data)
        return
            response
            .filter { $0.mode == "primary" || $0.mode == "all" }
            .map { $0.domain() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func reply(
        to permission: PermissionRequest,
        response: PermissionResponse,
        directory: String
    ) async throws {
        struct Body: Encodable {
            let response: PermissionResponse
        }

        let body = try encoder.encode(Body(response: response))
        _ = try await send(
            path: "/session/\(permission.sessionID)/permissions/\(permission.id)",
            method: "POST",
            directory: directory,
            body: body
        )
    }

    func events() throws -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        let request = try makeRequest(path: "/global/event", method: "GET", body: nil, queryItems: [])
        let session = session

        return AsyncThrowingStream { continuation in
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
                        guard let data = parser.consume(line: line) else { continue }
                        let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: data)
                        continuation.yield(OpenCodeEventMapper.domain(from: envelope))
                    }
                    if let data = parser.finish() {
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
        body: Data? = nil,
        accepting: Range<Int> = 200..<300
    ) async throws -> Data {
        var query = additionalQuery
        if let directory, !directory.isEmpty {
            query.insert(URLQueryItem(name: "directory", value: directory), at: 0)
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
        request.timeoutInterval = path == "/global/event" ? 3_600 : 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        if path == "/global/event" {
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

extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

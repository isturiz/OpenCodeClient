import Foundation
import Testing

@testable import OpenCodeClient

struct OpenCodeClientRequestTests {
    @Test func sendsBasicAuthAndDirectoryOnScopedRequest() async throws {
        let host = "opencode-auth.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data(#"{"data":[],"cursor":{}}"#.utf8))
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host, prefix: "/gateway", username: "mobile", password: "secret")

        _ = try await client.sessions(directory: "/tmp/My Project")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path() == "/gateway/api/session")
        #expect(query(request) == [URLQueryItem(name: "directory", value: "/tmp/My Project")])
        #expect(request.header("Authorization") == "Basic bW9iaWxlOnNlY3JldA==")
        #expect(request.header("Accept") == "application/json")
    }

    @Test func sendsPromptAfterSwitchingSessionModelAndAgent() async throws {
        let host = "opencode-prompt.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            let isPrompt = request.url?.path().hasSuffix("/prompt") == true
            return (
                try makeHTTPResponse(for: request, status: isPrompt ? 200 : 204),
                isPrompt ? Data(#"{"data":{"id":"msg_accepted"}}"#.utf8) : Data()
            )
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let model = ModelOption(
            providerID: "provider", modelID: "model", providerName: "Provider",
            name: "Model", isConnected: true, variant: "high"
        )
        let agent = AgentOption(
            name: "Display name", description: nil, mode: "primary", isBuiltIn: false, agentID: "build")

        try await client.promptAsync(
            sessionID: "ses_1", directory: "/tmp/project", text: "  Ship it  ", model: model, agent: agent
        )

        #expect(
            recorder.requests.map { $0.url?.path() } == [
                "/api/session/ses_1/model", "/api/session/ses_1/agent", "/api/session/ses_1/prompt",
            ])
        let modelBody = try jsonBody(recorder.requests[0])
        #expect(
            modelBody["model"] as? [String: String] == [
                "id": "model", "providerID": "provider", "variant": "high",
            ])
        #expect(try jsonBody(recorder.requests[1])["agent"] as? String == "build")
        let prompt = try jsonBody(recorder.requests[2])
        #expect(prompt["text"] as? String == "Ship it")
        #expect((prompt["id"] as? String)?.hasPrefix("msg_") == true)
        #expect(prompt["parts"] == nil)
        #expect(prompt["model"] == nil)
        for request in recorder.requests {
            #expect(request.method == "POST")
            #expect(query(request) == [URLQueryItem(name: "directory", value: "/tmp/project")])
        }
    }

    @Test func serverDefaultsDoNotSendSelectionRequests() async throws {
        let host = "opencode-defaults.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data(#"{"data":{}}"#.utf8))
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        try await client.promptAsync(
            sessionID: "ses_1", directory: "/tmp/project", text: "Hi", model: nil, agent: nil)
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.url?.path() == "/api/session/ses_1/prompt")
    }

    @Test func createsSessionInSelectedLocation() async throws {
        let host = "opencode-create.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), sessionResponse(id: "ses_new"))
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let session = try await client.createSession(directory: "/tmp/My Project", title: nil)

        let request = try #require(recorder.requests.first)
        #expect(request.method == "POST")
        #expect(request.url?.path() == "/api/session")
        #expect(query(request).first == URLQueryItem(name: "directory", value: "/tmp/My Project"))
        #expect(session.id == "ses_new")
        let body = try jsonBody(request)
        #expect(body["location"] as? [String: String] == ["directory": "/tmp/My Project"])
        #expect(body["title"] == nil)
    }

    @Test func scopesModelsAndVisiblePrimaryAgentsToSelectedLocation() async throws {
        let host = "opencode-options.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            let data: Data
            if request.url?.path() == "/api/model" {
                data = Data(
                    #"{"data":[{"id":"model-alias","modelID":"upstream-model","providerID":"provider","name":"Model","enabled":true,"variants":[{"id":"high"}]}]}"#
                        .utf8)
            } else {
                data = Data(
                    #"{"data":[{"id":"build","name":"Build","mode":"primary","hidden":false},{"id":"hidden","name":"Hidden","mode":"primary","hidden":true},{"id":"child","name":"Child","mode":"subagent","hidden":false}]}"#
                        .utf8)
            }
            return (try makeHTTPResponse(for: request), data)
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let models = try await client.models(directory: "/tmp/Selected Project")
        let agents = try await client.agents(directory: "/tmp/Selected Project")

        #expect(models.map(\.id) == ["provider/model-alias", "provider/model-alias#high"])
        #expect(agents.map(\.id) == ["build"])
        for request in recorder.requests {
            #expect(query(request).contains(URLQueryItem(name: "directory", value: "/tmp/Selected Project")))
            #expect(
                query(request).contains(
                    URLQueryItem(name: "location[directory]", value: "/tmp/Selected Project")))
        }
    }

    @Test func supportsSessionReviewAndRawProjectFiles() async throws {
        let host = "opencode-review.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            if request.httpMethod == "PATCH" {
                return (try makeHTTPResponse(for: request, status: 204), Data())
            }
            let data: Data
            switch request.url?.path() {
            case "/api/session/ses_1": data = sessionResponse(title: "Renamed")
            case "/api/session/ses_1/diff":
                data = Data(
                    #"{"data":[{"file":"Sources/App.swift","status":"modified","additions":3,"deletions":1,"patch":"@@ patch"}]}"#
                        .utf8)
            case "/api/fs/list": data = Data(#"{"data":[{"path":"Sources","type":"directory"}]}"#.utf8)
            case "/api/fs/read/Sources/App.swift": data = Data("import SwiftUI".utf8)
            default: throw URLError(.badURL)
            }
            return (try makeHTTPResponse(for: request), data)
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let directory = "/tmp/Project"
        let session = try await client.updateSessionTitle(
            sessionID: "ses_1", directory: directory, title: "  Renamed  ")
        let diff = try await client.sessionDiff(sessionID: "ses_1", directory: directory)
        let files = try await client.files(directory: directory, path: "")
        let content = try await client.fileContent(directory: directory, path: "Sources/App.swift")

        #expect(session.title == "Renamed")
        #expect(diff.first?.path == "Sources/App.swift")
        #expect(files.first?.name == "Sources")
        #expect(files.first?.type == .directory)
        #expect(content == OpenCodeFileContent(type: .text, content: "import SwiftUI"))
        #expect(recorder.requests.first?.method == "PATCH")
        #expect(try jsonBody(recorder.requests[0])["title"] as? String == "Renamed")
        for request in recorder.requests {
            #expect(query(request).first == URLQueryItem(name: "directory", value: directory))
        }
    }

    @Test func rawBinaryFilesAndSpecialCharactersAreHandledSafely() async throws {
        let host = "opencode-binary.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data([0, 255, 1]))
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let file = try await client.fileContent(directory: "/tmp/project", path: "Images/a #?%.png")
        #expect(file.type == .binary)
        #expect(file.content == nil)
        let request = try #require(recorder.requests.first)
        #expect(request.header("Accept") == "*/*")
        #expect(request.url?.path(percentEncoded: false) == "/api/fs/read/Images/a #?%.png")
        #expect(request.url?.fragment == nil)
        #expect(query(request).count == 2)
    }

    @Test func followsSessionAndMessagePaginationWithoutRepeatingOrder() async throws {
        let host = "opencode-pages.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let nextPage = components?.queryItems?.contains { $0.name == "cursor" } == true
            let data: Data
            if request.url?.path() == "/api/session" {
                let id = nextPage ? "ses_old" : "ses_new"
                let session =
                    #"{"id":"\#(id)","projectID":"project","location":{"directory":"/tmp/project"},"time":{"created":1000,"updated":2000}}"#
                data = Data(
                    "{\"data\":[\(session)],\"cursor\":\(nextPage ? "{}" : "{\"next\":\"sessions-next\"}")}"
                        .utf8)
            } else {
                let id = nextPage ? "msg_old" : "msg_new"
                data = Data(
                    "{\"data\":[{\"id\":\"\(id)\",\"type\":\"user\",\"time\":{\"created\":1000},\"text\":\"Hi\"}],\"cursor\":\(nextPage ? "{}" : "{\"next\":\"messages-next\"}")}"
                        .utf8)
            }
            return (try makeHTTPResponse(for: request), data)
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        #expect(try await client.sessions(directory: "/tmp/project").count == 2)
        let messages = try await client.messages(sessionID: "ses_1", directory: "/tmp/project", limit: 2)
        #expect(messages.map(\.id) == ["msg_old", "msg_new"])
        #expect(query(recorder.requests[2]).contains(URLQueryItem(name: "order", value: "desc")))
        #expect(!query(recorder.requests[3]).contains { $0.name == "order" })
        #expect(query(recorder.requests[3]).contains(URLQueryItem(name: "cursor", value: "messages-next")))
    }

    @Test func recoversPendingPermissionsAndRepliesWithDecision() async throws {
        let host = "opencode-permissions.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            if request.httpMethod == "POST" {
                return (try makeHTTPResponse(for: request, status: 204), Data())
            }
            return (
                try makeHTTPResponse(for: request),
                Data(
                    #"{"data":[{"id":"per_1","sessionID":"ses_1","action":"edit","resources":["*.swift"]}]}"#
                        .utf8)
            )
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        let permissions = try await client.permissions(sessionID: "ses_1", directory: "/tmp/project")
        let permission = try #require(permissions.first)
        try await client.reply(to: permission, response: .once, directory: "/tmp/project")
        #expect(recorder.requests.last?.url?.path() == "/api/session/ses_1/permission/per_1/reply")
        #expect(try jsonBody(recorder.requests[1])["decision"] as? String == "once")
    }

    @Test func activeSessionsAndInterruptUseV2Routes() async throws {
        let host = "opencode-active.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data(#"{"data":{"ses_1":{"type":"running"}}}"#.utf8))
        }
        defer { MockURLProtocol.unregister(host: host) }
        let client = try makeClient(host: host)
        #expect(try await client.sessionStatuses(directory: "/tmp/project")["ses_1"] == .busy)
        try await client.abort(sessionID: "ses_1", directory: "/tmp/project")
        #expect(query(recorder.requests[1]).contains(URLQueryItem(name: "resume", value: "false")))
        #expect(
            recorder.requests.map { $0.url?.path() } == [
                "/api/session/active", "/api/session/ses_1/interrupt",
            ])
    }

    @Test func healthDoesNotPinServerRelease() async throws {
        let host = "opencode-health.example.com"
        MockURLProtocol.register(host: host) { request in
            #expect(request.url?.path() == "/api/info")
            return (
                try makeHTTPResponse(for: request),
                Data(#"{"version":"2.999.0","pid":1,"futureCapability":true}"#.utf8)
            )
        }
        defer { MockURLProtocol.unregister(host: host) }
        #expect(try await makeClient(host: host).health().version == "2.999.0")
    }

    @Test func missingV2APIReportsCompatibilityError() async throws {
        let host = "opencode-v1.example.com"
        MockURLProtocol.register(host: host) { request in
            (try makeHTTPResponse(for: request, status: 404), Data())
        }
        defer { MockURLProtocol.unregister(host: host) }
        await #expect(throws: NetworkError.unsupportedServerVersion) {
            _ = try await makeClient(host: host).health()
        }
    }

    @Test func mapsStructuredHTTPError() async throws {
        let host = "opencode-error.example.com"
        MockURLProtocol.register(host: host) { request in
            (try makeHTTPResponse(for: request, status: 401), Data(#"{"message":"Unauthorized"}"#.utf8))
        }
        defer { MockURLProtocol.unregister(host: host) }
        await #expect(throws: NetworkError.httpStatus(401, "Unauthorized")) {
            _ = try await makeClient(host: host).health()
        }
    }

    @Test func emptyPromptDoesNotSendRequest() async throws {
        let host = "opencode-empty-prompt.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data())
        }
        defer { MockURLProtocol.unregister(host: host) }
        try await makeClient(host: host).promptAsync(
            sessionID: "ses_1", directory: "/tmp/project", text: "  \n ", model: nil, agent: nil
        )
        #expect(recorder.requests.isEmpty)
    }
}

private func makeClient(
    host: String, prefix: String = "", username: String = "", password: String? = nil
) throws -> LiveOpenCodeClient {
    try LiveOpenCodeClient(
        configuration: OpenCodeClientConfiguration(
            profile: ServerProfile(name: "Test", baseURL: "https://\(host)\(prefix)", username: username),
            password: password
        ),
        session: makeMockSession()
    )
}

private func query(_ request: RecordedRequest) -> [URLQueryItem] {
    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}

private func jsonBody(_ request: RecordedRequest) throws -> [String: Any] {
    let body = try #require(request.body)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func sessionResponse(id: String = "ses_1", title: String = "New session") -> Data {
    Data(
        #"{"data":{"id":"\#(id)","projectID":"project","location":{"directory":"/tmp/Project"},"title":"\#(title)","time":{"created":1000,"updated":2000}}}"#
            .utf8)
}

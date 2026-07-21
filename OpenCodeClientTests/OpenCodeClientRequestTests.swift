import Foundation
import Testing

@testable import OpenCodeClient

struct OpenCodeClientRequestTests {
    @Test func sendsBasicAuthAndDirectoryOnScopedRequest() async throws {
        let host = "opencode-auth.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request), Data("[]".utf8))
        }
        defer { MockURLProtocol.unregister(host: host) }

        let profile = ServerProfile(
            name: "Test",
            baseURL: "https://\(host)/api",
            username: "mobile"
        )
        let client = try LiveOpenCodeClient(
            configuration: OpenCodeClientConfiguration(profile: profile, password: "secret"),
            session: makeMockSession()
        )

        _ = try await client.sessions(directory: "/tmp/My Project")

        let request = try #require(recorder.requests.first)
        let queryItems = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        )
        #expect(request.url?.path() == "/api/session")
        #expect(queryItems == [URLQueryItem(name: "directory", value: "/tmp/My Project")])
        #expect(request.header("Authorization") == "Basic bW9iaWxlOnNlY3JldA==")
        #expect(request.header("Accept") == "application/json")
    }

    @Test func sendsPromptAsyncBodyAndAcceptsNoContent() async throws {
        let host = "opencode-prompt.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (try makeHTTPResponse(for: request, status: 204), Data())
        }
        defer { MockURLProtocol.unregister(host: host) }

        let profile = ServerProfile(name: "Test", baseURL: "https://\(host)")
        let client = try LiveOpenCodeClient(
            configuration: OpenCodeClientConfiguration(profile: profile, password: nil),
            session: makeMockSession()
        )
        let model = ModelOption(
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

        try await client.promptAsync(
            sessionID: "ses_1",
            directory: "/tmp/project",
            text: "  Ship it  ",
            model: model,
            agent: agent
        )

        let request = try #require(recorder.requests.first)
        #expect(request.method == "POST")
        #expect(request.url?.path() == "/session/ses_1/prompt_async")
        #expect(request.header("Content-Type") == "application/json")
        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let encodedModel = try #require(json["model"] as? [String: String])
        let parts = try #require(json["parts"] as? [[String: Any]])
        #expect(json["agent"] as? String == "build")
        #expect(encodedModel == ["providerID": "openai", "modelID": "gpt-5.6-sol"])
        #expect(parts.first?["type"] as? String == "text")
        #expect(parts.first?["text"] as? String == "Ship it")
    }

    @Test func mapsStructuredHTTPError() async throws {
        let host = "opencode-error.example.com"
        MockURLProtocol.register(host: host) { request in
            (
                try makeHTTPResponse(for: request, status: 401),
                Data(#"{"message":"Unauthorized"}"#.utf8)
            )
        }
        defer { MockURLProtocol.unregister(host: host) }

        let profile = ServerProfile(name: "Test", baseURL: "https://\(host)")
        let client = try LiveOpenCodeClient(
            configuration: OpenCodeClientConfiguration(profile: profile, password: nil),
            session: makeMockSession()
        )

        do {
            _ = try await client.health()
            Issue.record("Expected an HTTP status error")
        } catch {
            #expect(error as? NetworkError == .httpStatus(401, "Unauthorized"))
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

        let profile = ServerProfile(name: "Test", baseURL: "https://\(host)")
        let client = try LiveOpenCodeClient(
            configuration: OpenCodeClientConfiguration(profile: profile, password: nil),
            session: makeMockSession()
        )

        try await client.promptAsync(
            sessionID: "ses_1",
            directory: "/tmp/project",
            text: "  \n ",
            model: nil,
            agent: nil
        )

        #expect(recorder.requests.isEmpty)
    }
}

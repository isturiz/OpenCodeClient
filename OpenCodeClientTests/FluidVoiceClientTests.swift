import Foundation
import Testing

@testable import OpenCodeClient

struct FluidVoiceClientTests {
    @Test func healthAndTranscriptionUsePublishedContract() async throws {
        let host = "fluidvoice.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            switch request.url?.path() {
            case "/v1/health":
                return (
                    try makeHTTPResponse(for: request),
                    Data(#"{"status":"ok","version":"1.6.4"}"#.utf8)
                )
            case "/v1/transcribe":
                return (
                    try makeHTTPResponse(for: request),
                    Data(
                        #"{"text":"Hello","confidence":0.99,"sampleCount":16000,"provider":"Parakeet"}"#.utf8
                    )
                )
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { MockURLProtocol.unregister(host: host) }

        let client = try LiveFluidVoiceClient(
            configuration: FluidVoiceClientConfiguration(
                baseURL: "https://\(host)",
                username: "voice",
                password: "secret"
            ),
            session: makeMockSession()
        )
        let health = try await client.health()
        #expect(health.isHealthy)
        #expect(health.version == "1.6.4")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data(repeating: 0, count: 128).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transcription = try await client.transcribe(fileURL: fileURL)
        #expect(transcription.text == "Hello")
        #expect(transcription.sampleCount == 16_000)

        let upload = try #require(recorder.requests.last)
        #expect(upload.method == "POST")
        #expect(upload.url?.path() == "/v1/transcribe")
        #expect(upload.header("Content-Type") == "audio/wav")
        #expect(upload.header("X-Filename") == "dictation.wav")
        #expect(
            recorder.requests.allSatisfy {
                $0.header("Authorization") == "Basic dm9pY2U6c2VjcmV0"
            }
        )
    }

    @Test func postprocessEncodesTextAndReturnsResult() async throws {
        let host = "fluidvoice-postprocess.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (
                try makeHTTPResponse(for: request),
                Data(#"{"text":"Polished text","provider":"mlx","model":"fixture"}"#.utf8)
            )
        }
        defer { MockURLProtocol.unregister(host: host) }

        let client = try LiveFluidVoiceClient(
            configuration: FluidVoiceClientConfiguration(
                baseURL: "https://\(host)",
                username: "voice",
                password: "secret"
            ),
            session: makeMockSession()
        )
        let result = try await client.postprocess(text: "rough text")

        #expect(result == "Polished text")
        let request = try #require(recorder.requests.first)
        #expect(request.url?.path() == "/v1/postprocess")
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Authorization") == "Basic dm9pY2U6c2VjcmV0")
        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["text": "rough text"])
    }

    @Test func rejectsEmptyRecordingBeforeNetwork() async throws {
        let client = try LiveFluidVoiceClient(
            configuration: FluidVoiceClientConfiguration(
                baseURL: "https://fluidvoice-empty.example.com",
                username: "",
                password: nil
            ),
            session: makeMockSession()
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await client.transcribe(fileURL: fileURL)
            Issue.record("Expected an empty recording error")
        } catch {
            #expect(error as? VoiceRecordingError == .emptyRecording)
        }
    }

    @Test func omitsAuthorizationWithoutPassword() async throws {
        let host = "fluidvoice-no-auth.example.com"
        let recorder = RequestRecorder()
        MockURLProtocol.register(host: host) { request in
            recorder.append(request)
            return (
                try makeHTTPResponse(for: request),
                Data(#"{"status":"ok","version":"1.6.4"}"#.utf8)
            )
        }
        defer { MockURLProtocol.unregister(host: host) }

        let client = try LiveFluidVoiceClient(
            configuration: FluidVoiceClientConfiguration(
                baseURL: "https://\(host)",
                username: "voice",
                password: nil
            ),
            session: makeMockSession()
        )

        _ = try await client.health()

        #expect(recorder.requests.first?.header("Authorization") == nil)
    }
}

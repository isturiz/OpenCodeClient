import Foundation

struct FluidVoiceHealth: Equatable, Sendable {
    let status: String
    let version: String

    var isHealthy: Bool {
        status.lowercased() == "ok"
    }
}

struct FluidVoiceTranscription: Equatable, Sendable {
    let text: String
    let confidence: Double
    let sampleCount: Int
    let provider: String
}

private struct FluidVoiceHealthDTO: Decodable, Sendable {
    let status: String
    let version: String
}

private struct FluidVoiceTranscriptionDTO: Decodable, Sendable {
    let text: String
    let confidence: Double
    let sampleCount: Int
    let provider: String
}

private struct FluidVoicePostprocessDTO: Decodable, Sendable {
    let text: String
    let provider: String
    let model: String
}

private struct FluidVoicePostprocessBody: Encodable, Sendable {
    let text: String
}

protocol FluidVoiceClientProtocol: Sendable {
    func health() async throws -> FluidVoiceHealth
    func transcribe(fileURL: URL) async throws -> FluidVoiceTranscription
    func postprocess(text: String) async throws -> String
    func transcribe(fileURL: URL, postprocess: Bool) async throws -> String
}

actor LiveFluidVoiceClient: FluidVoiceClientProtocol {
    static let maximumUploadBytes = 25 * 1_024 * 1_024

    private let baseURL: URL
    private let username: String
    private let password: String?
    private let http: HTTPClient
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(configuration: FluidVoiceClientConfiguration, session: URLSession = .shared) throws {
        baseURL = try ServerURLPolicy.normalizedURL(from: configuration.baseURL)
        username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        password = configuration.password?.isEmpty == false ? configuration.password : nil
        http = HTTPClient(session: session)
    }

    func health() async throws -> FluidVoiceHealth {
        let request = try request(path: "/v1/health")
        let data = try await http.data(for: request)
        do {
            let response = try decoder.decode(FluidVoiceHealthDTO.self, from: data)
            return FluidVoiceHealth(status: response.status, version: response.version)
        } catch {
            throw NetworkError.decoding
        }
    }

    func transcribe(fileURL: URL) async throws -> FluidVoiceTranscription {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else {
            throw VoiceRecordingError.emptyRecording
        }
        guard size <= Self.maximumUploadBytes else {
            throw VoiceRecordingError.recordingTooLarge
        }

        var request = try request(path: "/v1/transcribe", method: "POST")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("dictation.wav", forHTTPHeaderField: "X-Filename")
        let data = try await http.upload(for: request, fromFile: fileURL)

        do {
            let response = try decoder.decode(FluidVoiceTranscriptionDTO.self, from: data)
            return FluidVoiceTranscription(
                text: response.text,
                confidence: response.confidence,
                sampleCount: response.sampleCount,
                provider: response.provider
            )
        } catch {
            throw NetworkError.decoding
        }
    }

    func postprocess(text: String) async throws -> String {
        var request = try request(path: "/v1/postprocess", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(FluidVoicePostprocessBody(text: text))
        let data = try await http.data(for: request)

        do {
            return try decoder.decode(FluidVoicePostprocessDTO.self, from: data).text
        } catch {
            throw NetworkError.decoding
        }
    }

    func transcribe(fileURL: URL, postprocess: Bool) async throws -> String {
        let result = try await transcribe(fileURL: fileURL)
        guard postprocess else { return result.text }
        return try await self.postprocess(text: result.text)
    }

    private func request(path: String, method: String = "GET") throws -> URLRequest {
        let url = try ServerURLPolicy.appending(path: path, to: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let password {
            let credential = "\(username):\(password)"
            request.setValue(
                "Basic \(Data(credential.utf8).base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }
}

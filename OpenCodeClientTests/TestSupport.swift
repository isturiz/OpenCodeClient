import Foundation

final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
        }
    }

    static func unregister(host: String) {
        _ = lock.withLock {
            handlers.removeValue(forKey: host)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host().map { handler(for: $0) != nil } ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let host = request.url?.host(),
            let handler = Self.handler(for: host)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func handler(for host: String) -> Handler? {
        lock.withLock { handlers[host] }
    }
}

func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

func makeHTTPResponse(for request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
    guard
        let url = request.url,
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    else {
        throw URLError(.badServerResponse)
    }
    return response
}

struct RecordedRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?

    init(_ request: URLRequest) {
        url = request.url
        method = request.httpMethod
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return result }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RecordedRequest] = []

    func append(_ request: URLRequest) {
        lock.withLock {
            storage.append(RecordedRequest(request))
        }
    }

    var requests: [RecordedRequest] {
        lock.withLock { storage }
    }
}

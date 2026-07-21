import Foundation

actor HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest, accepting acceptedStatuses: Range<Int> = 200..<300) async throws
        -> Data
    {
        do {
            let (data, response) = try await session.data(for: request)
            return try validate(data: data, response: response, accepting: acceptedStatuses)
        } catch {
            throw NetworkError.map(error)
        }
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        accepting acceptedStatuses: Range<Int> = 200..<300
    ) async throws -> Data {
        do {
            let (data, response) = try await session.upload(for: request, fromFile: fileURL)
            return try validate(data: data, response: response, accepting: acceptedStatuses)
        } catch {
            throw NetworkError.map(error)
        }
    }

    private func validate(data: Data, response: URLResponse, accepting statuses: Range<Int>) throws
        -> Data
    {
        guard let response = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard statuses.contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data)
            throw NetworkError.httpStatus(response.statusCode, envelope?.bestMessage)
        }
        return data
    }
}

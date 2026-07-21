import Foundation

enum NetworkError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case insecureRemoteURL
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding
    case timedOut
    case cancelled
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "Enter a valid URL including http:// or https://.")
        case .insecureRemoteURL:
            String(localized: "Remote servers must use HTTPS. HTTP is allowed only on a local network.")
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
        case let .httpStatus(status, message):
            if let message, !message.isEmpty {
                String(localized: "Server returned HTTP \(status): \(message)")
            } else {
                String(localized: "Server returned HTTP \(status).")
            }
        case .decoding:
            String(localized: "The server response is not compatible with this app version.")
        case .timedOut:
            String(localized: "The request timed out. Check the server and your network connection.")
        case .cancelled:
            String(localized: "The request was cancelled.")
        case let .unreachable(detail):
            String(localized: "Could not reach the server: \(detail)")
        }
    }

    static func map(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            default:
                return .unreachable(urlError.localizedDescription)
            }
        }
        if error is DecodingError {
            return .decoding
        }
        return .unreachable(error.localizedDescription)
    }
}

struct ServerErrorEnvelope: Decodable, Sendable {
    let error: String?
    let message: String?

    var bestMessage: String? {
        error ?? message
    }
}

import Foundation

enum ServerURLKind: Equatable, Sendable {
    case localHTTP
    case secureRemote
}

enum ServerURLPolicy {
    static func normalizedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty,
            components.query == nil,
            components.fragment == nil
        else {
            throw NetworkError.invalidURL
        }

        if scheme == "http", !isLocalHost(host) {
            throw NetworkError.insecureRemoteURL
        }

        components.scheme = scheme
        while components.percentEncodedPath.count > 1 && components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        return url
    }

    static func kind(of url: URL) -> ServerURLKind {
        if url.scheme?.lowercased() == "http" {
            return .localHTTP
        }
        return .secureRemote
    }

    static func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }

        if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") {
            return true
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }

    static func appending(path: String, to baseURL: URL, queryItems: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }

        guard !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        components.queryItems = queryItems
        guard let result = components.url else {
            throw NetworkError.invalidURL
        }
        return result
    }
}

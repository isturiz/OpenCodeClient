import Foundation

struct ServerProfile: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var baseURL: String
    var username: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        username: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.createdAt = createdAt
    }

    var displayAddress: String {
        guard let components = URLComponents(string: baseURL), let host = components.host else {
            return baseURL
        }

        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }
}

struct VoiceConfiguration: Codable, Equatable, Sendable {
    var baseURL: String
    var username: String
    var usesPostProcessing: Bool

    init(baseURL: String, username: String = "", usesPostProcessing: Bool) {
        self.baseURL = baseURL
        self.username = username
        self.usesPostProcessing = usesPostProcessing
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case username
        case usesPostProcessing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        usesPostProcessing = try container.decode(Bool.self, forKey: .usesPostProcessing)
    }

    static let empty = VoiceConfiguration(baseURL: "", username: "", usesPostProcessing: false)
}

struct SettingsSnapshot: Equatable, Sendable {
    var profiles: [ServerProfile]
    var activeProfileID: UUID?
    var voice: VoiceConfiguration

    var activeProfile: ServerProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }
}

struct OpenCodeClientConfiguration: Equatable, Sendable {
    let profile: ServerProfile
    let password: String?
}

struct FluidVoiceClientConfiguration: Equatable, Sendable {
    let baseURL: String
    let username: String
    let password: String?
}

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

struct VoiceProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var baseURL: String
    var username: String
    var usesPostProcessing: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        username: String = "",
        usesPostProcessing: Bool,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.usesPostProcessing = usesPostProcessing
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

enum SessionOrganization: String, Codable, Equatable, Sendable {
    case project
    case chronology
    case projectThenChronology

    var groupsByProject: Bool {
        self != .chronology
    }

    var groupsByChronology: Bool {
        self != .project
    }

    func settingProjectGrouping(_ isEnabled: Bool) -> SessionOrganization {
        switch (self, isEnabled) {
        case (.project, false):
            return .project
        case (.projectThenChronology, false):
            return .chronology
        case (.chronology, true):
            return .projectThenChronology
        default:
            return self
        }
    }

    func settingChronologyGrouping(_ isEnabled: Bool) -> SessionOrganization {
        switch (self, isEnabled) {
        case (.chronology, false):
            return .chronology
        case (.projectThenChronology, false):
            return .project
        case (.project, true):
            return .projectThenChronology
        default:
            return self
        }
    }
}

struct PinnedSessionReference: Codable, Equatable, Hashable, Sendable {
    let profileID: UUID
    let sessionID: String
}

struct SettingsSnapshot: Equatable, Sendable {
    var profiles: [ServerProfile]
    var activeProfileID: UUID?
    var voiceProfiles: [VoiceProfile]
    var activeVoiceProfileID: UUID?
    var sessionOrganization: SessionOrganization
    var pinnedSessions: Set<PinnedSessionReference>

    init(
        profiles: [ServerProfile],
        activeProfileID: UUID?,
        voiceProfiles: [VoiceProfile] = [],
        activeVoiceProfileID: UUID? = nil,
        sessionOrganization: SessionOrganization = .project,
        pinnedSessions: Set<PinnedSessionReference> = []
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.voiceProfiles = voiceProfiles
        self.activeVoiceProfileID = activeVoiceProfileID
        self.sessionOrganization = sessionOrganization
        self.pinnedSessions = pinnedSessions
    }

    var activeProfile: ServerProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var activeVoiceProfile: VoiceProfile? {
        guard let activeVoiceProfileID else { return nil }
        return voiceProfiles.first { $0.id == activeVoiceProfileID }
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

import Foundation

protocol SettingsStoring: Sendable {
    func snapshot() async -> SettingsSnapshot
    func upsert(_ profile: ServerProfile, password: String?) async throws
    func delete(profileID: UUID) async throws
    func setActive(profileID: UUID?) async
    func password(for profileID: UUID) async throws -> String?
    func fluidVoicePassword() async throws -> String?
    func saveVoiceConfiguration(_ configuration: VoiceConfiguration, password: String?) async throws
}

actor SettingsRepository: SettingsStoring {
    private enum Keys {
        static let profiles = "settings.serverProfiles.v1"
        static let activeProfileID = "settings.activeProfileID.v1"
        static let voice = "settings.voice.v1"
    }

    private let defaults: UserDefaults
    private let credentials: any CredentialStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, credentials: any CredentialStoring = KeychainStore()) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func snapshot() -> SettingsSnapshot {
        let profiles = load([ServerProfile].self, forKey: Keys.profiles) ?? []
        let storedID = defaults.string(forKey: Keys.activeProfileID).flatMap(UUID.init(uuidString:))
        let activeID = profiles.contains(where: { $0.id == storedID }) ? storedID : profiles.first?.id
        let voice = load(VoiceConfiguration.self, forKey: Keys.voice) ?? .empty
        return SettingsSnapshot(profiles: profiles, activeProfileID: activeID, voice: voice)
    }

    func upsert(_ profile: ServerProfile, password: String?) async throws {
        var profiles = snapshot().profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save(profiles, forKey: Keys.profiles)

        if let password {
            if password.isEmpty {
                try await credentials.removePassword(for: profile.id)
            } else {
                try await credentials.setPassword(password, for: profile.id)
            }
        }

        if defaults.string(forKey: Keys.activeProfileID) == nil {
            defaults.set(profile.id.uuidString, forKey: Keys.activeProfileID)
        }
    }

    func delete(profileID: UUID) async throws {
        var current = snapshot()
        current.profiles.removeAll { $0.id == profileID }
        save(current.profiles, forKey: Keys.profiles)
        try await credentials.removePassword(for: profileID)

        if current.activeProfileID == profileID {
            if let next = current.profiles.first?.id {
                defaults.set(next.uuidString, forKey: Keys.activeProfileID)
            } else {
                defaults.removeObject(forKey: Keys.activeProfileID)
            }
        }
    }

    func setActive(profileID: UUID?) {
        if let profileID {
            defaults.set(profileID.uuidString, forKey: Keys.activeProfileID)
        } else {
            defaults.removeObject(forKey: Keys.activeProfileID)
        }
    }

    func password(for profileID: UUID) async throws -> String? {
        try await credentials.password(for: profileID)
    }

    func fluidVoicePassword() async throws -> String? {
        try await credentials.fluidVoicePassword()
    }

    func saveVoiceConfiguration(_ configuration: VoiceConfiguration, password: String?) async throws {
        save(configuration, forKey: Keys.voice)
        if let password {
            if password.isEmpty {
                try await credentials.removeFluidVoicePassword()
            } else {
                try await credentials.setFluidVoicePassword(password)
            }
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

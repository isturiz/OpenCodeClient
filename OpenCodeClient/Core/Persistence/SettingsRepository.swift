import Foundation

protocol SettingsStoring: Sendable {
    func snapshot() async -> SettingsSnapshot
    func upsert(_ profile: ServerProfile, password: String?) async throws
    func delete(profileID: UUID) async throws
    func setActive(profileID: UUID?) async
    func password(for profileID: UUID) async throws -> String?
    func upsertVoiceProfile(_ profile: VoiceProfile, password: String?) async throws
    func deleteVoiceProfile(profileID: UUID) async throws
    func setActiveVoiceProfile(profileID: UUID?) async
    func voicePassword(for profileID: UUID) async throws -> String?
    func saveSessionOrganization(_ organization: SessionOrganization) async throws
    func savePinnedSessions(_ references: Set<PinnedSessionReference>) async throws
}

enum SettingsStorageError: Error, Equatable, LocalizedError, Sendable {
    case corruptVoiceProfiles
    case voiceMigrationIncomplete

    var errorDescription: String? {
        switch self {
        case .corruptVoiceProfiles:
            String(localized: "The saved Voice profiles could not be read and were not changed.")
        case .voiceMigrationIncomplete:
            String(localized: "The existing Voice configuration could not be migrated safely.")
        }
    }
}

actor SettingsRepository: SettingsStoring {
    private enum Keys {
        static let profiles = "settings.serverProfiles.v1"
        static let activeProfileID = "settings.activeProfileID.v1"
        static let legacyVoice = "settings.voice.v1"
        static let voiceProfiles = "settings.voiceProfiles.v2"
        static let activeVoiceProfileID = "settings.activeVoiceProfileID.v2"
        static let sessionOrganization = "settings.sessionOrganization.v1"
        static let pinnedSessions = "settings.pinnedSessions.v1"
    }

    private struct LegacyVoiceConfiguration: Decodable {
        let baseURL: String
        let username: String
        let usesPostProcessing: Bool

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
    }

    private struct VoiceState {
        var profiles: [VoiceProfile]
        var activeProfileID: UUID?
    }

    private static let migratedVoiceProfileID = UUID(
        uuidString: "B589EDB4-FE5D-4E76-8C15-BB21CEB5EFA5"
    )!

    private let defaults: UserDefaults
    private let credentials: any CredentialStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var voiceStorageIsCorrupt = false
    private var legacyVoiceMigrationPending = false
    private var transactionInProgress = false
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard, credentials: any CredentialStoring = KeychainStore()) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func snapshot() async -> SettingsSnapshot {
        await acquireTransaction()
        defer { releaseTransaction() }
        return await makeSnapshot()
    }

    private func makeSnapshot() async -> SettingsSnapshot {
        let profiles = load([ServerProfile].self, forKey: Keys.profiles) ?? []
        let storedID = defaults.string(forKey: Keys.activeProfileID).flatMap(UUID.init(uuidString:))
        let activeID = profiles.contains(where: { $0.id == storedID }) ? storedID : profiles.first?.id
        let voiceState = await loadVoiceState()
        let organization = load(SessionOrganization.self, forKey: Keys.sessionOrganization) ?? .project
        let pinnedSessions = load(Set<PinnedSessionReference>.self, forKey: Keys.pinnedSessions) ?? []
        return SettingsSnapshot(
            profiles: profiles,
            activeProfileID: activeID,
            voiceProfiles: voiceState.profiles,
            activeVoiceProfileID: voiceState.activeProfileID,
            sessionOrganization: organization,
            pinnedSessions: pinnedSessions
        )
    }

    func upsert(_ profile: ServerProfile, password: String?) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        var profiles = await makeSnapshot().profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let previousPassword: String?
        if password != nil {
            previousPassword = try await credentials.password(for: profile.id)
        } else {
            previousPassword = nil
        }
        if let password {
            if password.isEmpty {
                try await credentials.removePassword(for: profile.id)
            } else {
                try await credentials.setPassword(password, for: profile.id)
            }
        }
        do {
            try save(profiles, forKey: Keys.profiles)
        } catch {
            if password != nil {
                try? await restoreServerPassword(previousPassword, profileID: profile.id)
            }
            throw error
        }

        if defaults.string(forKey: Keys.activeProfileID) == nil {
            defaults.set(profile.id.uuidString, forKey: Keys.activeProfileID)
        }
    }

    func delete(profileID: UUID) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        var current = await makeSnapshot()
        current.profiles.removeAll { $0.id == profileID }
        current.pinnedSessions = current.pinnedSessions.filter { $0.profileID != profileID }
        let previousPassword = try await credentials.password(for: profileID)
        try await credentials.removePassword(for: profileID)
        do {
            try save(current.profiles, forKey: Keys.profiles)
            try save(current.pinnedSessions, forKey: Keys.pinnedSessions)
        } catch {
            try? await restoreServerPassword(previousPassword, profileID: profileID)
            throw error
        }

        if current.activeProfileID == profileID {
            if let next = current.profiles.first?.id {
                defaults.set(next.uuidString, forKey: Keys.activeProfileID)
            } else {
                defaults.removeObject(forKey: Keys.activeProfileID)
            }
        }
    }

    func setActive(profileID: UUID?) async {
        await acquireTransaction()
        defer { releaseTransaction() }
        if let profileID {
            defaults.set(profileID.uuidString, forKey: Keys.activeProfileID)
        } else {
            defaults.removeObject(forKey: Keys.activeProfileID)
        }
    }

    func password(for profileID: UUID) async throws -> String? {
        await acquireTransaction()
        defer { releaseTransaction() }
        return try await credentials.password(for: profileID)
    }

    func upsertVoiceProfile(_ profile: VoiceProfile, password: String?) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        var profiles = await makeSnapshot().voiceProfiles
        guard !voiceStorageIsCorrupt else {
            throw SettingsStorageError.corruptVoiceProfiles
        }
        guard !legacyVoiceMigrationPending else {
            throw SettingsStorageError.voiceMigrationIncomplete
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let previousPassword: String?
        if password != nil {
            previousPassword = try await credentials.voicePassword(for: profile.id)
        } else {
            previousPassword = nil
        }
        if let password {
            if password.isEmpty {
                try await credentials.removeVoicePassword(for: profile.id)
            } else {
                try await credentials.setVoicePassword(password, for: profile.id)
            }
        }
        do {
            try save(profiles, forKey: Keys.voiceProfiles)
        } catch {
            if password != nil {
                try? await restoreVoicePassword(previousPassword, profileID: profile.id)
            }
            throw error
        }
    }

    func deleteVoiceProfile(profileID: UUID) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        var current = await makeSnapshot()
        guard !voiceStorageIsCorrupt else {
            throw SettingsStorageError.corruptVoiceProfiles
        }
        guard !legacyVoiceMigrationPending else {
            throw SettingsStorageError.voiceMigrationIncomplete
        }
        current.voiceProfiles.removeAll { $0.id == profileID }
        let previousPassword = try await credentials.voicePassword(for: profileID)
        try await credentials.removeVoicePassword(for: profileID)
        do {
            try save(current.voiceProfiles, forKey: Keys.voiceProfiles)
        } catch {
            try? await restoreVoicePassword(previousPassword, profileID: profileID)
            throw error
        }

        if current.activeVoiceProfileID == profileID {
            defaults.removeObject(forKey: Keys.activeVoiceProfileID)
        }
    }

    func setActiveVoiceProfile(profileID: UUID?) async {
        await acquireTransaction()
        defer { releaseTransaction() }
        guard let profileID else {
            defaults.removeObject(forKey: Keys.activeVoiceProfileID)
            return
        }
        let profiles = await makeSnapshot().voiceProfiles
        guard !voiceStorageIsCorrupt, !legacyVoiceMigrationPending else { return }
        guard profiles.contains(where: { $0.id == profileID }) else {
            defaults.removeObject(forKey: Keys.activeVoiceProfileID)
            return
        }
        defaults.set(profileID.uuidString, forKey: Keys.activeVoiceProfileID)
    }

    func voicePassword(for profileID: UUID) async throws -> String? {
        await acquireTransaction()
        defer { releaseTransaction() }
        if let password = try await credentials.voicePassword(for: profileID) {
            return password
        }
        let hasMigratedProfiles = defaults.data(forKey: Keys.voiceProfiles) != nil
        if profileID == Self.migratedVoiceProfileID, !hasMigratedProfiles {
            return try await credentials.legacyFluidVoicePassword()
        }
        return nil
    }

    func saveSessionOrganization(_ organization: SessionOrganization) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        try save(organization, forKey: Keys.sessionOrganization)
    }

    func savePinnedSessions(_ references: Set<PinnedSessionReference>) async throws {
        await acquireTransaction()
        defer { releaseTransaction() }
        try save(references, forKey: Keys.pinnedSessions)
    }

    private func loadVoiceState() async -> VoiceState {
        if defaults.data(forKey: Keys.voiceProfiles) != nil {
            guard let profiles = load([VoiceProfile].self, forKey: Keys.voiceProfiles) else {
                voiceStorageIsCorrupt = true
                return VoiceState(profiles: [], activeProfileID: nil)
            }
            voiceStorageIsCorrupt = false
            legacyVoiceMigrationPending = false
            let storedID = defaults.string(forKey: Keys.activeVoiceProfileID).flatMap(UUID.init(uuidString:))
            let activeID = profiles.contains(where: { $0.id == storedID }) ? storedID : nil
            if defaults.data(forKey: Keys.legacyVoice) != nil {
                do {
                    try await credentials.removeLegacyFluidVoicePassword()
                    defaults.removeObject(forKey: Keys.legacyVoice)
                } catch {
                    // Keep the legacy marker so cleanup is retried on the next snapshot.
                }
            }
            return VoiceState(profiles: profiles, activeProfileID: activeID)
        }

        voiceStorageIsCorrupt = false

        guard let legacy = load(LegacyVoiceConfiguration.self, forKey: Keys.legacyVoice) else {
            legacyVoiceMigrationPending = false
            return VoiceState(profiles: [], activeProfileID: nil)
        }
        guard !legacy.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            legacyVoiceMigrationPending = false
            do {
                try await credentials.removeLegacyFluidVoicePassword()
                defaults.removeObject(forKey: Keys.legacyVoice)
            } catch {
                // Keep the legacy marker so cleanup is retried on the next snapshot.
            }
            return VoiceState(profiles: [], activeProfileID: nil)
        }

        let profile = VoiceProfile(
            id: Self.migratedVoiceProfileID,
            name: Self.migratedVoiceName(from: legacy.baseURL),
            baseURL: legacy.baseURL,
            username: legacy.username,
            usesPostProcessing: legacy.usesPostProcessing,
            createdAt: .distantPast
        )

        do {
            if let password = try await credentials.legacyFluidVoicePassword(), !password.isEmpty {
                try await credentials.setVoicePassword(password, for: profile.id)
            }
            try save([profile], forKey: Keys.voiceProfiles)
            defaults.set(profile.id.uuidString, forKey: Keys.activeVoiceProfileID)

            guard load([VoiceProfile].self, forKey: Keys.voiceProfiles)?.first == profile else {
                throw CocoaError(.fileWriteUnknown)
            }

        } catch {
            legacyVoiceMigrationPending = true
            return VoiceState(profiles: [profile], activeProfileID: profile.id)
        }
        legacyVoiceMigrationPending = false

        do {
            try await credentials.removeLegacyFluidVoicePassword()
            defaults.removeObject(forKey: Keys.legacyVoice)
        } catch {
            // The v2 profile is valid. Keep the marker so legacy cleanup is retried.
        }

        return VoiceState(profiles: [profile], activeProfileID: profile.id)
    }

    private static func migratedVoiceName(from baseURL: String) -> String {
        guard let host = URLComponents(string: baseURL)?.host, !host.isEmpty else {
            return "FluidVoice"
        }
        return host
    }

    private func restoreServerPassword(_ password: String?, profileID: UUID) async throws {
        if let password {
            try await credentials.setPassword(password, for: profileID)
        } else {
            try await credentials.removePassword(for: profileID)
        }
    }

    private func restoreVoicePassword(_ password: String?, profileID: UUID) async throws {
        if let password {
            try await credentials.setVoicePassword(password, for: profileID)
        } else {
            try await credentials.removeVoicePassword(for: profileID)
        }
    }

    private func acquireTransaction() async {
        if !transactionInProgress {
            transactionInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            transactionWaiters.append(continuation)
        }
    }

    private func releaseTransaction() {
        if transactionWaiters.isEmpty {
            transactionInProgress = false
        } else {
            transactionWaiters.removeFirst().resume()
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }
}

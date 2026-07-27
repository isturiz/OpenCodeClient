import Foundation
import Testing

@testable import OpenCodeClient

private enum MemoryCredentialsError: Error {
    case rejected
}

private actor MemoryCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    private var voiceValues: [UUID: String] = [:]
    private var legacyVoiceValue: String?
    private var rejectsMutations = false

    func password(for profileID: UUID) -> String? {
        values[profileID]
    }

    func setPassword(_ password: String, for profileID: UUID) throws {
        if rejectsMutations { throw MemoryCredentialsError.rejected }
        values[profileID] = password
    }

    func removePassword(for profileID: UUID) throws {
        if rejectsMutations { throw MemoryCredentialsError.rejected }
        values[profileID] = nil
    }

    func voicePassword(for profileID: UUID) -> String? {
        voiceValues[profileID]
    }

    func setVoicePassword(_ password: String, for profileID: UUID) throws {
        if rejectsMutations { throw MemoryCredentialsError.rejected }
        voiceValues[profileID] = password
    }

    func removeVoicePassword(for profileID: UUID) throws {
        if rejectsMutations { throw MemoryCredentialsError.rejected }
        voiceValues[profileID] = nil
    }

    func legacyFluidVoicePassword() -> String? {
        legacyVoiceValue
    }

    func removeLegacyFluidVoicePassword() throws {
        if rejectsMutations { throw MemoryCredentialsError.rejected }
        legacyVoiceValue = nil
    }

    func seedLegacyVoicePassword(_ password: String) {
        legacyVoiceValue = password
    }

    func rejectMutations() {
        rejectsMutations = true
    }
}

struct SettingsRepositoryTests {
    @Test func organizationAlwaysKeepsAtLeastOneGroupingEnabled() {
        #expect(SessionOrganization.project.settingProjectGrouping(false) == .project)
        #expect(SessionOrganization.chronology.settingChronologyGrouping(false) == .chronology)
        #expect(SessionOrganization.project.settingChronologyGrouping(true) == .projectThenChronology)
        #expect(
            SessionOrganization.projectThenChronology.settingProjectGrouping(false) == .chronology
        )
    }

    @Test func persistsSettingsAndKeepsPasswordsOutOfDefaults() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentials()
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: credentials
        )
        let profile = ServerProfile(
            name: "Mac",
            baseURL: "https://mac.example.com",
            username: "opencode"
        )
        let voiceProfile = VoiceProfile(
            name: "Voice",
            baseURL: "https://voice.example.com",
            username: "voice",
            usesPostProcessing: true
        )

        try await repository.upsert(profile, password: "secret")
        await repository.setActive(profileID: profile.id)
        try await repository.upsertVoiceProfile(voiceProfile, password: "voice-secret")
        await repository.setActiveVoiceProfile(profileID: voiceProfile.id)
        try await repository.saveSessionOrganization(.projectThenChronology)

        let snapshot = await repository.snapshot()
        let password = try await repository.password(for: profile.id)
        let voicePassword = try await repository.voicePassword(for: voiceProfile.id)
        #expect(snapshot.activeProfile == profile)
        #expect(snapshot.activeVoiceProfile == voiceProfile)
        #expect(snapshot.sessionOrganization == .projectThenChronology)
        #expect(password == "secret")
        #expect(voicePassword == "voice-secret")

        let storedValues = try #require(UserDefaults(suiteName: suite)).dictionaryRepresentation().values
        for value in storedValues {
            if let data = value as? Data {
                #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
            } else if let string = value as? String {
                #expect(!string.contains("secret"))
            }
        }
    }

    @Test func deletingActiveProfileSelectsNextProfileAndRemovesCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentials()
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: credentials
        )
        let first = ServerProfile(name: "One", baseURL: "https://one.example.com")
        let second = ServerProfile(name: "Two", baseURL: "https://two.example.com")
        try await repository.upsert(first, password: "first-secret")
        try await repository.upsert(second, password: nil)
        await repository.setActive(profileID: first.id)

        try await repository.delete(profileID: first.id)

        let snapshot = await repository.snapshot()
        let deletedPassword = try await repository.password(for: first.id)
        #expect(snapshot.profiles == [second])
        #expect(snapshot.activeProfileID == second.id)
        #expect(deletedPassword == nil)
    }

    @Test func deletingActiveVoiceProfileDisablesVoiceAndRemovesCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let first = VoiceProfile(
            name: "One",
            baseURL: "https://one.example.com",
            usesPostProcessing: false
        )
        let second = VoiceProfile(
            name: "Two",
            baseURL: "https://two.example.com",
            usesPostProcessing: true
        )
        try await repository.upsertVoiceProfile(first, password: "voice-secret")
        try await repository.upsertVoiceProfile(second, password: nil)
        await repository.setActiveVoiceProfile(profileID: first.id)

        try await repository.deleteVoiceProfile(profileID: first.id)

        let snapshot = await repository.snapshot()
        let deletedPassword = try await repository.voicePassword(for: first.id)
        #expect(snapshot.voiceProfiles == [second])
        #expect(snapshot.activeVoiceProfileID == nil)
        #expect(deletedPassword == nil)
    }

    @Test func emptyPasswordsRemoveExistingCredentials() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let profile = ServerProfile(name: "Mac", baseURL: "https://mac.example.com")
        let voiceProfile = VoiceProfile(
            name: "Voice",
            baseURL: "https://voice.example.com",
            usesPostProcessing: false
        )

        try await repository.upsert(profile, password: "secret")
        try await repository.upsert(profile, password: "")
        try await repository.upsertVoiceProfile(voiceProfile, password: "voice-secret")
        try await repository.upsertVoiceProfile(voiceProfile, password: "")

        #expect(try await repository.password(for: profile.id) == nil)
        #expect(try await repository.voicePassword(for: voiceProfile.id) == nil)
    }

    @Test func migratesLegacyVoiceConfigurationAndCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let seedDefaults = try #require(UserDefaults(suiteName: suite))
        seedDefaults.set(
            Data(#"{"baseURL":"https://voice.example.com","usesPostProcessing":true}"#.utf8),
            forKey: "settings.voice.v1"
        )
        let credentials = MemoryCredentials()
        await credentials.seedLegacyVoicePassword("legacy-secret")
        let repository = SettingsRepository(defaults: seedDefaults, credentials: credentials)

        let snapshot = await repository.snapshot()
        let profile = try #require(snapshot.activeVoiceProfile)

        #expect(snapshot.voiceProfiles.count == 1)
        #expect(profile.name == "voice.example.com")
        #expect(profile.username.isEmpty)
        #expect(profile.usesPostProcessing)
        #expect(try await repository.voicePassword(for: profile.id) == "legacy-secret")
        let storedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(storedDefaults.data(forKey: "settings.voice.v1") == nil)
        #expect(await credentials.legacyFluidVoicePassword() == nil)

        let repeatedSnapshot = await repository.snapshot()
        #expect(repeatedSnapshot == snapshot)
    }

    @Test func profilesCanRemainSavedWithNoActiveVoiceProfile() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let profile = VoiceProfile(
            name: "Voice",
            baseURL: "https://voice.example.com",
            usesPostProcessing: false
        )
        try await repository.upsertVoiceProfile(profile, password: nil)

        await repository.setActiveVoiceProfile(profileID: profile.id)
        await repository.setActiveVoiceProfile(profileID: nil)

        let snapshot = await repository.snapshot()
        #expect(snapshot.voiceProfiles == [profile])
        #expect(snapshot.activeVoiceProfileID == nil)
    }

    @Test func failedCredentialUpdateDoesNotCommitServerMetadata() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentials()
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: credentials
        )
        let profile = ServerProfile(name: "Mac", baseURL: "https://old.example.com")
        try await repository.upsert(profile, password: "old-secret")
        await credentials.rejectMutations()
        var edited = profile
        edited.baseURL = "https://new.example.com"

        do {
            try await repository.upsert(edited, password: "new-secret")
            Issue.record("Expected the credential update to fail")
        } catch {
            #expect(error is MemoryCredentialsError)
        }

        let snapshot = await repository.snapshot()
        #expect(snapshot.profiles == [profile])
        #expect(try await repository.password(for: profile.id) == "old-secret")
    }

    @Test func corruptVoiceStorageIsNotOverwritten() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let corruptData = Data("not-json".utf8)
        let seedDefaults = try #require(UserDefaults(suiteName: suite))
        seedDefaults.set(corruptData, forKey: "settings.voiceProfiles.v2")
        let repository = SettingsRepository(
            defaults: seedDefaults,
            credentials: MemoryCredentials()
        )
        let profile = VoiceProfile(
            name: "Voice",
            baseURL: "https://voice.example.com",
            usesPostProcessing: false
        )

        _ = await repository.snapshot()
        do {
            try await repository.upsertVoiceProfile(profile, password: nil)
            Issue.record("Expected corrupt storage to reject the update")
        } catch {
            #expect(error as? SettingsStorageError == .corruptVoiceProfiles)
        }

        let storedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(storedDefaults.data(forKey: "settings.voiceProfiles.v2") == corruptData)
    }

    @Test func concurrentProfileUpdatesDoNotOverwriteEachOther() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let first = ServerProfile(name: "One", baseURL: "https://one.example.com")
        let second = ServerProfile(name: "Two", baseURL: "https://two.example.com")

        async let firstUpdate: Void = repository.upsert(first, password: "one")
        async let secondUpdate: Void = repository.upsert(second, password: "two")
        _ = try await (firstUpdate, secondUpdate)

        let snapshot = await repository.snapshot()
        #expect(Set(snapshot.profiles.map(\.id)) == Set([first.id, second.id]))
    }

    @Test func failedLegacyMigrationBlocksVoiceMutationsAndKeepsCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let seedDefaults = try #require(UserDefaults(suiteName: suite))
        seedDefaults.set(
            Data(
                #"{"baseURL":"https://voice.example.com","usesPostProcessing":false}"#.utf8
            ),
            forKey: "settings.voice.v1"
        )
        let credentials = MemoryCredentials()
        await credentials.seedLegacyVoicePassword("legacy-secret")
        await credentials.rejectMutations()
        let repository = SettingsRepository(defaults: seedDefaults, credentials: credentials)
        let snapshot = await repository.snapshot()
        let migratedProfile = try #require(snapshot.activeVoiceProfile)

        do {
            try await repository.upsertVoiceProfile(migratedProfile, password: nil)
            Issue.record("Expected the incomplete migration to block the update")
        } catch {
            #expect(error as? SettingsStorageError == .voiceMigrationIncomplete)
        }

        let storedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(storedDefaults.data(forKey: "settings.voiceProfiles.v2") == nil)
        #expect(await credentials.legacyFluidVoicePassword() == "legacy-secret")
    }
}

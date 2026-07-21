import Foundation
import Testing

@testable import OpenCodeClient

private actor MemoryCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    private var voiceValue: String?

    func password(for profileID: UUID) async throws -> String? {
        values[profileID]
    }

    func setPassword(_ password: String, for profileID: UUID) async throws {
        values[profileID] = password
    }

    func removePassword(for profileID: UUID) async throws {
        values[profileID] = nil
    }

    func fluidVoicePassword() async throws -> String? {
        voiceValue
    }

    func setFluidVoicePassword(_ password: String) async throws {
        voiceValue = password
    }

    func removeFluidVoicePassword() async throws {
        voiceValue = nil
    }
}

struct SettingsRepositoryTests {
    @Test func persistsSettingsAndKeepsPasswordOutOfDefaults() async throws {
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

        try await repository.upsert(profile, password: "secret")
        await repository.setActive(profileID: profile.id)
        try await repository.saveVoiceConfiguration(
            VoiceConfiguration(
                baseURL: "https://voice.example.com",
                username: "voice",
                usesPostProcessing: true
            ),
            password: "voice-secret"
        )

        let snapshot = await repository.snapshot()
        let password = try await repository.password(for: profile.id)
        let voicePassword = try await repository.fluidVoicePassword()
        #expect(snapshot.activeProfile == profile)
        #expect(snapshot.voice.username == "voice")
        #expect(snapshot.voice.usesPostProcessing)
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

    @Test func deletingActiveProfileSelectsNextProfileAndCredential() async throws {
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

    @Test func emptyPasswordRemovesExistingCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let profile = ServerProfile(name: "Mac", baseURL: "https://mac.example.com")

        try await repository.upsert(profile, password: "secret")
        try await repository.upsert(profile, password: "")

        let password = try await repository.password(for: profile.id)
        #expect(password == nil)
    }

    @Test func emptyFluidVoicePasswordRemovesExistingCredential() async throws {
        let suite = "SettingsRepositoryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: try #require(UserDefaults(suiteName: suite)),
            credentials: MemoryCredentials()
        )
        let configuration = VoiceConfiguration(
            baseURL: "https://voice.example.com",
            username: "voice",
            usesPostProcessing: false
        )

        try await repository.saveVoiceConfiguration(configuration, password: "voice-secret")
        try await repository.saveVoiceConfiguration(configuration, password: "")

        let password = try await repository.fluidVoicePassword()
        #expect(password == nil)
    }

    @Test func decodesVoiceConfigurationSavedBeforeUsernameSupport() throws {
        let data = Data(
            #"{"baseURL":"https://voice.example.com","usesPostProcessing":true}"#.utf8
        )

        let configuration = try JSONDecoder().decode(VoiceConfiguration.self, from: data)

        #expect(configuration.baseURL == "https://voice.example.com")
        #expect(configuration.username.isEmpty)
        #expect(configuration.usesPostProcessing)
    }
}

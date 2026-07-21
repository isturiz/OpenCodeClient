import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ServerProfile] = []
    private(set) var activeProfileID: UUID?
    private(set) var voiceConfiguration: VoiceConfiguration = .empty
    private(set) var hasLoaded = false
    var presentedError: String?

    @ObservationIgnored private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var activeProfile: ServerProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    func load() async {
        let snapshot = await dependencies.settings.snapshot()
        profiles = snapshot.profiles
        activeProfileID = snapshot.activeProfileID
        voiceConfiguration = snapshot.voice
        hasLoaded = true
    }

    func save(profile: ServerProfile, password: String?, makeActive: Bool = false) async throws {
        var normalized = profile
        normalized.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.baseURL = try ServerURLPolicy.normalizedURL(from: profile.baseURL).absoluteString
        normalized.username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)

        try await dependencies.settings.upsert(normalized, password: password)
        if makeActive || activeProfileID == nil {
            await dependencies.settings.setActive(profileID: normalized.id)
        }
        await load()
    }

    func delete(profileID: UUID) async throws {
        try await dependencies.settings.delete(profileID: profileID)
        await load()
    }

    func activate(profileID: UUID) async {
        await dependencies.settings.setActive(profileID: profileID)
        await load()
    }

    func saveVoiceConfiguration(_ configuration: VoiceConfiguration, password: String?) async throws {
        var normalized = configuration
        if !configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.baseURL = try ServerURLPolicy.normalizedURL(from: configuration.baseURL).absoluteString
        }
        normalized.username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        try await dependencies.settings.saveVoiceConfiguration(normalized, password: password)
        await load()
    }

    func configuration(for profile: ServerProfile) async throws -> OpenCodeClientConfiguration {
        let password = try await dependencies.settings.password(for: profile.id)
        return OpenCodeClientConfiguration(profile: profile, password: password)
    }

    func password(for profileID: UUID) async throws -> String {
        try await dependencies.settings.password(for: profileID) ?? ""
    }

    func client(for profile: ServerProfile) async throws -> any OpenCodeClientProtocol {
        let configuration = try await configuration(for: profile)
        return try dependencies.makeOpenCodeClient(configuration)
    }

    func activeClient() async throws -> any OpenCodeClientProtocol {
        guard let activeProfile else {
            throw NetworkError.invalidURL
        }
        return try await client(for: activeProfile)
    }

    func fluidVoicePassword() async throws -> String {
        try await dependencies.settings.fluidVoicePassword() ?? ""
    }

    func fluidVoiceClient() async throws -> any FluidVoiceClientProtocol {
        let baseURL = voiceConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            throw NetworkError.invalidURL
        }
        let configuration = FluidVoiceClientConfiguration(
            baseURL: baseURL,
            username: voiceConfiguration.username,
            password: try await dependencies.settings.fluidVoicePassword()
        )
        return try dependencies.makeFluidVoiceClient(configuration)
    }

    func test(profile: ServerProfile, password: String) async throws -> OpenCodeHealth {
        var normalized = profile
        normalized.baseURL = try ServerURLPolicy.normalizedURL(from: profile.baseURL).absoluteString
        let configuration = OpenCodeClientConfiguration(
            profile: normalized,
            password: password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : password
        )
        return try await dependencies.makeOpenCodeClient(configuration).health()
    }

    func testFluidVoice(baseURL: String, username: String, password: String) async throws
        -> FluidVoiceHealth
    {
        let normalized = try ServerURLPolicy.normalizedURL(from: baseURL).absoluteString
        let configuration = FluidVoiceClientConfiguration(
            baseURL: normalized,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.isEmpty ? nil : password
        )
        return try await dependencies.makeFluidVoiceClient(configuration).health()
    }
}

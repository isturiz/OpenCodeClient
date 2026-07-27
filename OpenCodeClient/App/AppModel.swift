import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ServerProfile] = []
    private(set) var activeProfileID: UUID?
    private(set) var voiceProfiles: [VoiceProfile] = []
    private(set) var activeVoiceProfileID: UUID?
    private(set) var sessionOrganization: SessionOrganization = .project
    private(set) var serverConfigurationRevision = 0
    private(set) var voiceConfigurationRevision = 0
    private(set) var hasLoaded = false
    var presentedError: String?

    @ObservationIgnored private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var activeProfile: ServerProfile? {
        profile(withID: activeProfileID)
    }

    var activeVoiceProfile: VoiceProfile? {
        guard let activeVoiceProfileID else { return nil }
        return voiceProfiles.first { $0.id == activeVoiceProfileID }
    }

    func profile(withID id: UUID?) -> ServerProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func load() async {
        let snapshot = await dependencies.settings.snapshot()
        profiles = snapshot.profiles
        activeProfileID = snapshot.activeProfileID
        voiceProfiles = snapshot.voiceProfiles
        activeVoiceProfileID = snapshot.activeVoiceProfileID
        sessionOrganization = snapshot.sessionOrganization
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
        serverConfigurationRevision &+= 1
    }

    func delete(profileID: UUID) async throws {
        try await dependencies.settings.delete(profileID: profileID)
        await load()
        serverConfigurationRevision &+= 1
    }

    func activate(profileID: UUID) async {
        guard activeProfileID != profileID else { return }
        await dependencies.settings.setActive(profileID: profileID)
        await load()
        serverConfigurationRevision &+= 1
    }

    func saveVoiceProfile(_ profile: VoiceProfile, password: String?) async throws {
        let wasActive = activeVoiceProfileID == profile.id
        var normalized = profile
        normalized.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.baseURL = try ServerURLPolicy.normalizedURL(from: profile.baseURL).absoluteString
        normalized.username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        try await dependencies.settings.upsertVoiceProfile(normalized, password: password)
        await load()
        if wasActive {
            voiceConfigurationRevision &+= 1
        }
    }

    func deleteVoiceProfile(profileID: UUID) async throws {
        let wasActive = activeVoiceProfileID == profileID
        try await dependencies.settings.deleteVoiceProfile(profileID: profileID)
        await load()
        if wasActive {
            voiceConfigurationRevision &+= 1
        }
    }

    func activateVoiceProfile(profileID: UUID?) async {
        guard activeVoiceProfileID != profileID else { return }
        await dependencies.settings.setActiveVoiceProfile(profileID: profileID)
        await load()
        voiceConfigurationRevision &+= 1
    }

    func saveSessionOrganization(_ organization: SessionOrganization) async {
        guard sessionOrganization != organization else { return }
        sessionOrganization = organization
        do {
            try await dependencies.settings.saveSessionOrganization(organization)
        } catch {
            let snapshot = await dependencies.settings.snapshot()
            sessionOrganization = snapshot.sessionOrganization
            presentedError = error.localizedDescription
        }
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

    func voicePassword(for profileID: UUID) async throws -> String {
        try await dependencies.settings.voicePassword(for: profileID) ?? ""
    }

    func voiceClient(for profile: VoiceProfile) async throws -> any FluidVoiceClientProtocol {
        let configuration = FluidVoiceClientConfiguration(
            baseURL: profile.baseURL,
            username: profile.username,
            password: try await dependencies.settings.voicePassword(for: profile.id)
        )
        return try dependencies.makeFluidVoiceClient(configuration)
    }

    func activeVoiceClient() async throws -> any FluidVoiceClientProtocol {
        guard let activeVoiceProfile else {
            throw NetworkError.invalidURL
        }
        return try await voiceClient(for: activeVoiceProfile)
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

    func testVoice(profile: VoiceProfile, password: String) async throws -> FluidVoiceHealth {
        let normalized = try ServerURLPolicy.normalizedURL(from: profile.baseURL).absoluteString
        let configuration = FluidVoiceClientConfiguration(
            baseURL: normalized,
            username: profile.username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.isEmpty ? nil : password
        )
        return try await dependencies.makeFluidVoiceClient(configuration).health()
    }
}

import Foundation

struct AppDependencies: Sendable {
    let settings: any SettingsStoring
    let makeOpenCodeClient: @Sendable (OpenCodeClientConfiguration) throws -> any OpenCodeClientProtocol
    let makeFluidVoiceClient: @Sendable (FluidVoiceClientConfiguration) throws -> any FluidVoiceClientProtocol

    static let live = AppDependencies(
        settings: SettingsRepository(),
        makeOpenCodeClient: { try LiveOpenCodeClient(configuration: $0) },
        makeFluidVoiceClient: { try LiveFluidVoiceClient(configuration: $0) }
    )
}

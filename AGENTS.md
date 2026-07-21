# Repository instructions

## Product direction

OpenCode Client is a native iOS 26 and iPadOS 26 companion for remote OpenCode servers. Its primary
workflow is: inspect projects, enter a session, review agent output, and steer the agent by text or
FluidVoice dictation. It does not run OpenCode or language models on-device.

## Source layout

- `OpenCodeClient/App` contains the composition root and navigation.
- `OpenCodeClient/Core` contains reusable UI, networking, persistence, and security primitives.
- `OpenCodeClient/Integrations` contains OpenCode and FluidVoice transport code.
- `OpenCodeClient/Features` contains feature views and their observable models.
- `OpenCodeClientTests` mirrors production boundaries with Swift Testing.
- `OpenCodeClientUITests` contains a small number of end-to-end accessibility tests.

## Architecture rules

- Keep views declarative. Async orchestration belongs in `@MainActor @Observable` feature models.
- Keep network and credential operations in actors.
- Depend on protocols at feature boundaries and inject live implementations from `AppDependencies`.
- Keep wire DTOs separate from UI-facing domain models when the server contract may evolve.
- Every project-scoped OpenCode request must carry the selected `directory` query parameter.
- Unknown OpenCode event and part types must not make decoding the entire response fail.
- Never place passwords, tokens, audio, prompts, file contents, or server URLs in public logs.
- Store secrets in Keychain, never UserDefaults or source files.
- Do not bypass TLS trust evaluation or add broad App Transport Security exceptions.

## UI rules

- Use native SwiftUI navigation and iOS 26 Liquid Glass for controls, not content surfaces.
- Preserve Dynamic Type, VoiceOver, Reduce Motion, and a minimum 44-point hit target.
- Keep user-visible strings in `Localizable.xcstrings`; English is the development language.
- Use semantic colors from `AppTheme`; do not add ad-hoc brand colors in feature views.

## Build and validation

Run formatting, build, and tests sequentially:

```bash
xcrun swift-format lint --recursive --strict OpenCodeClient OpenCodeClientTests OpenCodeClientUITests
xcodebuild build -project OpenCodeClient.xcodeproj -scheme OpenCodeClient \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project OpenCodeClient.xcodeproj -scheme OpenCodeClient \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:OpenCodeClientTests CODE_SIGNING_ALLOWED=NO
```

Do not run build and test concurrently against the same DerivedData directory.

## Integration safety

- Do not stop, restart, or mutate a user's OpenCode server on port 4096.
- Live integration tests must use a separate temporary server and workspace.
- Do not change FluidVoice defaults or Tailscale configuration automatically.
- Voice tests should use fixtures; live transcription is a deliberate manual acceptance test.

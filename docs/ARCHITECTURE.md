# Architecture

## Goals

The architecture optimizes for an unstable remote API boundary, testable state transitions, native
platform behavior, and incremental feature growth without a global state object.

## Layers

`App` is the composition root. It creates dependencies, owns high-level routing, and selects onboarding
or the authenticated application shell.

`Core` contains reusable primitives. Networking is based on URLSession and typed errors. Persistence
stores non-secret profile data as Codable values. Security wraps Keychain. DesignSystem provides the
small semantic visual vocabulary used by every feature.

`Integrations` contains protocol adapters. OpenCode maps REST and SSE payloads to app models. FluidVoice
records no state beyond an individual request and accepts a standard WAV file produced by the audio
recorder.

`Features` owns screens and observable models. A feature model is isolated to the main actor, receives
protocol dependencies, exposes renderable state, and cancels stale work when its identity changes.

## Data ownership

OpenCode remains authoritative for projects, sessions, messages, status, models, agents, and permissions.
The app persists only server profiles, Keychain credentials, the selected profile, and voice settings.
Network responses are cached in memory and resynchronized after SSE reconnects.

## OpenCode transport

The initial compatibility target is OpenCode 1.18.3. The app uses `/global/health`, `/project`, `/session`,
`/session/status`, message and prompt endpoints, `/provider`, `/agent`, permission replies, and
`/global/event`. Project-scoped calls include `directory`. Unknown event and message part discriminators
are retained as unknown values rather than failing an entire payload.

The global SSE stream is one connection per active server. It is cancelled in the background and on
profile changes. Reconnect uses capped exponential backoff with jitter and is followed by REST
reconciliation.

## Voice transport

Audio capture is native AVFoundation. It writes PCM16 mono WAV at 16 kHz to a protected temporary file.
Stopping capture uploads the file to FluidVoice `/v1/transcribe`; optional post-processing calls
`/v1/postprocess`. Optional HTTP Basic credentials are applied to every FluidVoice request for protected
reverse proxies. The transcript is inserted into the composer for review and is never auto-submitted.

## Dependency policy

Foundation, SwiftUI, Observation, AVFoundation, Security, and OSLog cover infrastructure. Textual is the
only direct third-party dependency and is isolated behind `MarkdownContentView` because its public API is
pre-1.0.

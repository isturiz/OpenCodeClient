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
The app persists server and Voice profiles, Keychain credentials, active-profile choices, and the global
conversation-organization preference. Network responses are cached in memory and resynchronized after
SSE reconnects.

## OpenCode transport

The app uses the released V2 `/api/info`, `/api/project`, `/api/session`, `/api/session/active`,
`/api/model`, `/api/agent`, `/api/fs/*`, permission, and `/api/event` endpoints. There is no fixed server
patch-release requirement. Project-scoped calls include `directory`; location-scoped resources also
use the V2 `location[directory]` query. Session creation carries `location` in its body. Subsequent
session operations use the session's directory, which can differ from the project's canonical root.

Sessions and messages have cursor pagination. Messages are a typed timeline with assistant `content`,
not V1 `info`/`parts` envelopes. Model references use `id`, `providerID`, and optional `variant`; selecting
models or agents updates session state before sending a text prompt. Unknown message and content
discriminators are retained without decoding their future-specific fields.

The server-wide SSE stream carries direct `{type, location, data}` events. It is cancelled in the
background and on profile changes. Reconnect, including orderly EOF, uses capped exponential backoff
with jitter. Events are live-only: a connected marker reconciles the session, messages, active status,
and pending permissions. Timeline deltas trigger throttled authoritative reads, so continuous output
does not starve refresh and content ordinals do not need to be guessed. Stream failures and bounded
buffer overflow trigger recovery rather than silently losing pending permissions.

## Voice transport

Audio capture is native AVFoundation. It writes PCM16 mono WAV at 16 kHz to a protected temporary file.
Stopping capture uploads the file to FluidVoice `/v1/transcribe`; optional post-processing calls
`/v1/postprocess`. Optional HTTP Basic credentials are applied to every FluidVoice request for protected
reverse proxies. Direct Tailscale Serve needs no Basic credentials: tailnet rules control access, and
the proxy connects to FluidVoice on loopback. The transcript is inserted into the composer for review
and is never auto-submitted.

## Dependency policy

Foundation, SwiftUI, Observation, AVFoundation, Security, and OSLog cover infrastructure. Textual is the
only direct third-party dependency and is isolated behind `MarkdownContentView` because its public API is
pre-1.0.

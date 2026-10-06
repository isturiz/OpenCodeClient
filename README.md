# OpenCode Client

A native iOS and iPadOS client for [OpenCode](https://opencode.ai), designed for reviewing work,
steering coding agents, and dictating prompts from away from a keyboard.

> [!IMPORTANT]
> OpenCode Client is an independent community project. It is not built, endorsed, or supported by
> the OpenCode team.

## Status

The project is in active early development. The first milestone provides a complete vertical slice:

- Multiple OpenCode server profiles with optional HTTP Basic authentication
- Project and session browsing
- Real-time chat over REST and Server-Sent Events
- Tool, reasoning, status, and permission rendering
- Model and agent selection
- Multiple FluidVoice profiles and batch transcription through its local HTTP API
- Adaptive iPhone and iPad layouts built for iOS 26
- English and Spanish localization

## Requirements

- Xcode 26.6 or newer
- iOS or iPadOS 26.0 or newer
- A reachable server with the OpenCode V2 API (no fixed patch-release requirement)
- FluidVoice with its local HTTP API enabled for optional voice transcription

## Run OpenCode

Use Tailscale on the Mac and iPhone or iPad. Keep OpenCode on loopback and expose it privately through
Tailscale Serve, not Funnel. For an existing background service:

```bash
opencode service status
tailscale serve --bg --https=443 "$(opencode service status)"
```

Add the generated HTTPS base URL in OpenCode Client, without `/api`. Use the service's credentials
with username `opencode`; inspect the password locally with `opencode service get password`, never
share it or place it in source files. Existing Serve targets must be inspected before applying changes.
See [Setup](docs/SETUP.md) for separate native, Docker, and voice endpoints.

## Configure FluidVoice

Enable the FluidVoice local API and restart FluidVoice:

```bash
defaults write com.FluidApp.app LocalAPIEnabled -bool true
defaults write com.FluidApp.app LocalAPIPort -int 47733
```

FluidVoice intentionally accepts loopback clients only. A physical iPhone cannot connect directly to
port `47733`. Tailscale Serve connects to it locally and protects remote access through your tailnet:

```bash
tailscale serve --bg --https=9443 http://127.0.0.1:47733
```

Enter the generated HTTPS URL, including `:9443`, in Settings → Voice. Leave username and password
empty for direct Tailscale Serve access. Restrict access with tailnet rules and do not enable Funnel.
This setup does not need Caddy or its local certificates. Choose an unused HTTPS port rather than
overwriting another Serve target.

## Build

```bash
open OpenCodeClient.xcodeproj
```

Or from the command line:

```bash
xcodebuild build \
  -project OpenCodeClient.xcodeproj \
  -scheme OpenCodeClient \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Architecture

The app uses feature-oriented SwiftUI code, Swift Observation, Swift Concurrency, URLSession, and a
small set of protocol boundaries for deterministic tests. Server data remains authoritative; only
connection profiles, active profile choices, secrets, voice preferences, and conversation organization
are persisted locally.

See [Architecture](docs/ARCHITECTURE.md), [Setup](docs/SETUP.md), and
[Roadmap](docs/ROADMAP.md) for details.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before
opening a pull request. Security issues must follow [SECURITY.md](SECURITY.md).

## License

OpenCode Client is available under the [MIT License](LICENSE).

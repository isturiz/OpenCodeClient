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
- FluidVoice batch transcription through its local HTTP API
- Adaptive iPhone and iPad layouts built for iOS 26
- English and Spanish localization

## Requirements

- Xcode 26.6 or newer
- iOS or iPadOS 26.0 or newer
- OpenCode 1.18.3 or a compatible server
- FluidVoice 1.6.4 or newer for optional voice transcription

## Run OpenCode

OpenCode binds to loopback by default. To reach it from an iPhone or iPad on your trusted network,
start it on an address reachable by the device and protect it with a password:

```bash
OPENCODE_SERVER_PASSWORD='replace-me' \
  opencode serve --hostname 0.0.0.0 --port 4096
```

Then add `http://<mac-address>:4096` in OpenCode Client. Basic Auth over plain HTTP is only suitable
for a trusted local network. Prefer an HTTPS reverse proxy or Tailscale for remote access.

## Configure FluidVoice

Enable the FluidVoice local API and restart FluidVoice:

```bash
defaults write com.FluidApp.app LocalAPIEnabled -bool true
defaults write com.FluidApp.app LocalAPIPort -int 47733
```

FluidVoice intentionally accepts loopback clients only. A physical iPhone cannot connect directly to
port `47733`. The recommended setup is an authenticated Tailscale Serve proxy:

```bash
tailscale serve --bg http://127.0.0.1:47733
```

Enter the generated HTTPS URL in Settings → Voice. Do not expose FluidVoice's unauthenticated local
port directly to a LAN or the public internet. If an HTTPS reverse proxy such as Caddy protects the
endpoint with Basic Auth, enter its username and password in the same Voice settings. The password is
stored in Keychain.

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
connection profiles, secrets, and voice preferences are persisted locally.

See [Architecture](docs/ARCHITECTURE.md), [Setup](docs/SETUP.md), and
[Roadmap](docs/ROADMAP.md) for details.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before
opening a pull request. Security issues must follow [SECURITY.md](SECURITY.md).

## License

OpenCode Client is available under the [MIT License](LICENSE).

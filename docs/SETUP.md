# Development and server setup

## Apple development environment

Install Xcode 26.6, open `OpenCodeClient.xcodeproj`, and choose an iOS 26 simulator or device. The
repository commits the official OpenCode Client development team identifier. A Team ID is public
metadata, not a signing credential, and does not grant access to certificates or App Store Connect.
Simulator builds do not require an Apple Developer account. To run on a physical device, select your
own development team locally and do not commit personal signing changes.

## OpenCode on a trusted LAN

```bash
OPENCODE_SERVER_PASSWORD='replace-me' \
  opencode serve --hostname 0.0.0.0 --port 4096
```

Use the Mac's LAN address in the app. The default username is `opencode` unless
`OPENCODE_SERVER_USERNAME` is set. A firewall must allow the selected port.

## OpenCode through Tailscale

Keep OpenCode on loopback and proxy it over authenticated HTTPS:

```bash
opencode serve --hostname 127.0.0.1 --port 4096
tailscale serve --bg http://127.0.0.1:4096
```

Protect OpenCode with its own Basic Auth even when it is available only inside a tailnet.

## FluidVoice

Enable the local API, restart FluidVoice, and verify it on the Mac:

```bash
defaults write com.FluidApp.app LocalAPIEnabled -bool true
defaults write com.FluidApp.app LocalAPIPort -int 47733
curl http://127.0.0.1:47733/v1/health
```

Expose it only inside the tailnet:

```bash
tailscale serve --bg http://127.0.0.1:47733
```

If port 443 is already used by another Tailscale Serve target, configure a path or a separate Tailscale
service and enter the resulting base URL in the app.

### FluidVoice through Caddy

Keep FluidVoice on loopback and protect the HTTPS proxy with Basic Auth. Generate a password hash rather
than placing a plaintext password in the Caddyfile:

```bash
caddy hash-password --plaintext 'replace-me'
```

```caddyfile
voice.example.com {
    basic_auth {
        voice <paste-generated-hash>
    }
    reverse_proxy 127.0.0.1:47733
}
```

Enter the Caddy HTTPS URL, username, and original plaintext password in Settings → Voice. OpenCode Client
stores the password in iOS Keychain and sends HTTP Basic authentication to health, transcription, and
post-processing endpoints.

## Command-line validation

Use the commands documented in `AGENTS.md`. Live tests must not target a shared OpenCode workspace.

# Security policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting
for this repository. If that is unavailable, contact the maintainer privately through the address on
the maintainer's GitHub profile.

Include the affected version, reproduction steps, impact, and any suggested mitigation. Avoid sending
real credentials, recordings, prompts, or private source code.

## Security model

- OpenCode and FluidVoice proxy passwords are stored in iOS Keychain.
- FluidVoice audio is sent only to the URL explicitly configured by the user.
- The app does not disable certificate validation.
- Public HTTP endpoints are rejected; local HTTP is allowed with a visible warning.
- Basic Auth over HTTP is not confidential and should only be used on a trusted LAN.
- FluidVoice's local API has no application-level authentication and rejects non-loopback clients.
  Tailscale Serve connects to its loopback endpoint; restrict remote access with tailnet grants/ACLs.
  Serve does not add an application password, and Funnel must not be enabled for this API.
- OpenCode's own authentication remains enabled even behind Tailscale. Neither the app nor its setup
  requires Caddy, local CA certificates, or a fixed OpenCode patch release.

Only the latest release receives security fixes during early development.

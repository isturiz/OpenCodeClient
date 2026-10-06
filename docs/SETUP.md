# Development and server setup

## Apple development environment

Install Xcode 26.6, open `OpenCodeClient.xcodeproj`, and choose an iOS 26 simulator or device. The
repository commits the official OpenCode Client development team identifier. A Team ID is public
metadata, not a signing credential, and does not grant access to certificates or App Store Connect.
Simulator builds do not require an Apple Developer account. To run on a physical device, select your
own development team locally and do not commit personal signing changes.

## OpenCode V2 through Tailscale

Install Tailscale on the Mac and iPhone or iPad and join the same tailnet. The app uses the released
OpenCode V2 HTTP API; it does not require a particular patch release. Server version is informational.
Unknown message content and event types do not invalidate the entire response.

Keep OpenCode on loopback. For the existing shared background service, inspect its address and the
current proxy configuration first:

```bash
opencode service status
tailscale serve status
```

If HTTPS port 443 is available, proxy the current service address:

```bash
tailscale serve --bg --https=443 "$(opencode service status)"
```

Do not overwrite an existing target without confirming what it serves. The service address can change
when the service restarts; recheck its address and update only its Serve target when necessary.

Add the generated HTTPS **base URL** in Settings → Servers, without `/api`. OpenCode authentication
is separate from tailnet access. For a shared service, use username `opencode` and inspect its password
locally with `opencode service get password`. Do not share the output. The app stores credentials in
Keychain. Passwords formerly used by another proxy are not necessarily OpenCode credentials.

For a separate foreground server on a stable port instead:

```bash
OPENCODE_SERVER_PASSWORD='replace-me' \
  opencode serve --hostname 127.0.0.1 --port 4096
```

Proxy that address only after choosing an unused Serve port. Never stop the user's shared server to
run integration tests. Native and Docker OpenCode servers can coexist behind independent HTTPS ports:

| HTTPS port | Intended target |
| --- | --- |
| 443 | Native OpenCode service's current loopback address |
| 8443 | Existing Docker OpenCode endpoint |
| 9443 | FluidVoice at `127.0.0.1:47733` |

These are suggested allocations, not app defaults. Both OpenCode profiles use the same V2 adapter.

## FluidVoice

Enable the local API, restart FluidVoice, and verify it on the Mac:

```bash
defaults write com.FluidApp.app LocalAPIEnabled -bool true
defaults write com.FluidApp.app LocalAPIPort -int 47733
curl http://127.0.0.1:47733/v1/health
```

Expose it only inside the tailnet:

```bash
tailscale serve --bg --https=9443 http://127.0.0.1:47733
```

Enter the generated HTTPS URL including `:9443` in Settings → Voice. Leave Basic Authentication empty
when connecting directly through Tailscale Serve. Restrict access with tailnet grants/ACLs. Serve is
private to the tailnet; **do not enable Funnel** for either service.

### Why a proxy is still required

FluidVoice's local API accepts only connections originating from localhost. Its listener can appear as
`*:47733` in `lsof`, but the app rejects non-loopback peers. Tailscale Serve opens the backend connection
to `127.0.0.1`, so it replaces the old HTTPS proxy without modifying FluidVoice's restrictions.

The client uses `GET /v1/health`, uploads raw WAV with `Content-Length` to `POST /v1/transcribe`, and sends
`{"text":"..."}` to `POST /v1/postprocess` when enabled. The recording must fit below the complete
request limit; the app reserves headroom for HTTP headers. Transcription uses the speech model selected
in FluidVoice. Post-processing follows FluidVoice's settings, which may use a cloud provider.

### Retiring an old Caddy setup

Inventory all Caddy uses first, including custom launch agents (not only `brew services`). Validate
OpenCode and FluidVoice through their Tailscale HTTPS URLs before unloading the old launch agent.
Move its plist and configuration to a private backup outside the repository rather than deleting
certificates or credentials. Do not uninstall Caddy if another application depends on it.

On a new phone, create fresh profiles. Existing app installations can edit profile URLs and explicitly
clear obsolete proxy credentials; the app never silently discards Keychain entries.

## Command-line validation

Use the commands documented in `AGENTS.md`. Live tests must not target a shared OpenCode workspace.
Run `python3 scripts/validate-opencode-api.py` for a separate temporary server, database, and workspace.
It exercises contracts without running a language model. Voice tests use fixtures; actual dictation
from a physical phone is a deliberate manual acceptance test.

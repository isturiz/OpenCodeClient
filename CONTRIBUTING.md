# Contributing

Thank you for helping improve OpenCode Client.

## Before opening a change

1. Search existing issues and discussions.
2. Open an issue before starting a large feature or architectural change.
3. Keep pull requests focused on one behavior.
4. Never include credentials, private hostnames, transcripts, recordings, or proprietary source code.

## Development workflow

1. Use Xcode 26.6 or newer.
2. Create a branch from `main`.
3. Follow the boundaries and commands in `AGENTS.md`.
4. Add tests for network contracts and state transitions.
5. Validate both an iPhone and an iPad layout for UI changes.
6. Run formatter lint, build, and unit tests before opening a pull request.

## Commit and pull request guidance

- Explain the user-visible problem and the chosen solution.
- Call out OpenCode or FluidVoice contract assumptions explicitly.
- Include screenshots for meaningful visual changes in light and dark mode.
- Do not commit generated user data, certificates, private keys, provisioning profiles, or personal
  signing changes.
- Update documentation when behavior or setup changes.

By contributing, you agree that your contribution is licensed under the MIT License.

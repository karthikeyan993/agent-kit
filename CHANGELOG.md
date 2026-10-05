# Changelog

Changes that reach developers' machines. Newest first. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

## 0.1.0 - 2026-10-05

### Added

- `bootstrap.sh` sets up a Mac or Linux VM. It runs one script per step from `steps/`.
- Pinned tools in `config/mise.toml`: herdr 0.9.3, pi 1.0.2, node 24.21.0, gh 2.96.0, ripgrep 15.2.0, fd 10.5.0 and jq 1.8.2.
- pi defaults in `config/pi-settings.json`: GitHub Copilot, `gpt-6-luna`, `xhigh` thinking. A developer's own settings are kept.
- Team pi packages from `config/pi-packages.txt`. Adding, re-pinning and removing packages are all handled.
- herdr integration for pi.
- `scripts/doctor.sh` health check, `scripts/test-sandbox.sh` fresh-machine test and `scripts/lint.sh`.
- CI on macOS and Linux.

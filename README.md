# agent-kit

Our team's setup for AI coding agents. One command gives a developer's Mac or a GCP VM:

- **herdr**: a terminal workspace for running and watching many agents
- **pi**: the coding agent, using GitHub Copilot with `gpt-6-luna` at `xhigh` thinking
- **team skills**: installed as pi packages
- **everything they depend on**: at exact, pinned versions

## Quick start

```bash
git clone https://github.com/YOUR_ORG/agent-kit.git ~/agent-kit
```

```bash
~/agent-kit/bootstrap.sh
```

It takes a few minutes the first time. If you aren't logged in to GitHub yet, it opens the login in your browser. It finishes with a health check that shows anything left to do.

Then, once per machine:

1. Open a new terminal.
2. Run `pi` and type `/login`.
3. Choose **GitHub Copilot**. Leave the Enterprise domain blank unless we're on `*.ghe.com`.
4. Enter the code shown at github.com/login/device.
5. Run `herdr` and start working.

You can run the health check any time:

```bash
~/agent-kit/scripts/doctor.sh
```

## Staying up to date

```bash
git -C ~/agent-kit pull && ~/agent-kit/bootstrap.sh
```

Re-running is always safe. Don't use `herdr update` or `pi update self`; versions are managed in this repo.

## Remote agents on GCP

Run the same quick start on a GCP VM. Then you can do either:

- attach to it from your Mac with `herdr --remote`, or
- leave agents running there on their own.

See [docs/remote-gcp.md](docs/remote-gcp.md).

## What's in this repo

```
bootstrap.sh          Entry point: runs steps/ in order, then the health check
config/               Everything the team decides. Most PRs only touch this folder.
  mise.toml             Tools and their exact versions
  pi-settings.json      pi defaults: provider, model, thinking level
  pi-packages.txt       Skill packages every developer gets
steps/                One small script per setup step, run in filename order
lib/                  Shared helpers: logging, check output, settings merge rules
scripts/
  doctor.sh             Read-only health check
  test-sandbox.sh       Fresh-machine test in a throwaway HOME (CI runs it)
  lint.sh               Static checks (CI runs it)
docs/                 How it works, maintaining, remote VMs, troubleshooting, decisions
AGENTS.md             Instructions for coding agents working on this repo
```

## Documentation

| Read this | When you want to |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Understand what gets installed, and where |
| [docs/maintaining.md](docs/maintaining.md) | Bump a version, add a skill, change a default, or release |
| [docs/remote-gcp.md](docs/remote-gcp.md) | Run agents on a GCP VM |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Fix a failed check or a broken setup |
| [docs/decisions.md](docs/decisions.md) | Know why it's built this way |

## Requirements

- macOS, or Linux (Debian or Ubuntu), on x86_64 or arm64
- `git`, `curl` and `tar` (a new Mac gets them from `xcode-select --install`)
- A GitHub account with a Copilot seat

No admin rights are needed. Everything installs into your home directory.

## Getting help

Run `scripts/doctor.sh` and send its output to the owners listed in [.github/CODEOWNERS](.github/CODEOWNERS).

# agent-kit

One command sets up a Mac or a Linux VM for AI coding agents:

- **herdr**: a terminal workspace for running many agents
- **pi**: the coding agent, using GitHub Copilot (`gpt-6-luna`, `xhigh` thinking)
- **team skills**
- the tools these need, at pinned versions

## Set up

```bash
git clone https://github.com/YOUR_ORG/agent-kit.git ~/agent-kit
```

```bash
~/agent-kit/setup.sh
```

Partway through, setup opens pi so you can log in to GitHub Copilot:

1. Type `/login` and choose **GitHub Copilot**.
2. Type `/quit`, and setup continues.

When it's done, open a new terminal and run `herdr` to start working.

If a step fails, setup offers to open pi to diagnose and fix it. pi clears whatever blocked the setup, then re-runs it, so your machine still ends up the same as everyone else's.

## Add or remove a skill

Skills are listed in [apm.yml](apm.yml), one line each:

```yaml
dependencies:
  apm:
    - your-org/agent-skills/skills/code-review#v1.0.0   # one skill, pinned to a tag
    - your-org/more-skills                               # every skill in a repo
    - ./skills/my-skill                                  # a skill written in this repo
```

- **Add:** add a line. Alternatively, run `apm install <link>` in this folder, which adds the line for you.
- **Remove:** delete the line.

Then run `./setup.sh`, and commit `apm.yml` together with `apm.lock.yaml`.

## Keep up to date

| What happened | Run |
|---|---|
| Someone pushed changes to this repo | `git pull && ./setup.sh` |
| You edited `apm.yml`, `mise.toml` or `pi-settings.json` | `./setup.sh` |
| You want the newest versions of the skills | `./setup.sh --update`, then commit `apm.lock.yaml` |
| You want a newer tool | Change its version in `mise.toml`, then run `./setup.sh` (`mise outdated --bump` lists newer versions) |

`setup.sh` is always safe to re-run. Don't use `herdr update` or `pi update self`; versions come from this repo.

## What's in here

| File | Controls |
|---|---|
| `setup.sh` | Installs or updates everything |
| `mise.toml` | Tools and their versions |
| `apm.yml` | Skills |
| `pi-settings.json` | pi defaults. These keys are reset on every run; your other pi settings aren't touched. |
| `skills/` | Skills written in this repo |
| `scripts/test.sh` | For maintainers: runs `setup.sh` on a pretend new machine and checks the result |

## Remote agents on a GCP VM

1. Make `ssh devbox` work. Use `gcloud compute config-ssh`, or, for IAP-only VMs, add a `Host devbox` entry with:
   ```
   ProxyCommand gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --zone=ZONE --project=PROJECT
   ```
2. On the VM, follow "Set up" above. The Copilot login works over SSH.
3. Use it in either of two ways:
   - **From your Mac:** run `herdr machine add devbox` once, then `herdr --remote devbox`.
   - **On its own:** SSH in, run `herdr`, start agents and detach. They keep running until the VM reboots.

## Troubleshooting

| Problem | Fix |
|---|---|
| `setup.sh` failed | Accept its offer to open pi. Or, later, run `pi -a @.setup-failure.md` in this folder. |
| `pi` or `herdr` not found after setup | Open a new terminal. |
| An old `pi` (from npm or Homebrew) runs instead | Make the `mise activate` line the last line of `~/.zshrc`, or uninstall the old one. |
| pi says "The requested model is not supported" | Unset `COPILOT_GITHUB_TOKEN` and use `/login`. pi doesn't handle that variable correctly for Copilot. |
| `gpt-6-luna` isn't available | Your org's Copilot policy hasn't enabled it. Ask the Copilot admin. |
| herdr says the server version differs | When no agents are running: `herdr server stop`, then `herdr`. |
| Downloads fail at the office | `export HTTPS_PROXY=…`, then re-run `./setup.sh`. |

## Why these tools

- **mise** installs every tool from one file, on macOS and Linux, without admin rights.
- **APM** (Microsoft's Agent Package Manager) installs skills from links. Its lockfile keeps every machine on the same skill versions, and it removes a skill when its line is deleted.
- **Copilot `/login`** rather than a token: pi sends a token from the environment straight to Copilot, which rejected every request in our test.

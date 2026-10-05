# agent-kit

One command sets up a Mac or a Linux VM for AI coding agents:

- **herdr**: a terminal workspace for running many agents
- **pi**: the coding agent, using GitHub Copilot (`gpt-6-luna`, `xhigh` thinking)
- **team skills**
- the tools these need, at pinned versions

## Set up

On a new machine, nothing is installed yet and this repo is private, so first get mise, log in to GitHub, and clone with GitHub's `gh` (run through mise):

```bash
curl -fsSL https://mise.run | MISE_INSTALL_HELP=0 sh
```

```bash
~/.local/bin/mise x gh -- gh auth login --hostname github.com --git-protocol https --web
```

```bash
~/.local/bin/mise x gh -- gh repo clone YOUR_ORG/agent-kit ~/agent-kit
```

On a Mac, if a window asks to install the command line developer tools, accept, then run the last command again.

Then run setup:

```bash
~/agent-kit/setup.sh
```

Partway through, setup opens pi so you can log in to GitHub Copilot:

1. Type `/login` and choose **GitHub Copilot**.
2. Type `/quit`, and setup continues.

When it's done, open a new terminal and run `herdr` to start working.

If a step fails, setup offers to open pi to diagnose and fix it. pi clears whatever blocked the setup, then re-runs it, so your machine still ends up the same as everyone else's.

## Add or remove a skill

Skills from other repos go in the `packages` list in [pi-settings.json](pi-settings.json). Skills written in this repo are just folders in [skills/](skills/).

### Example: add Matt Pocock's grill-me

**1. Find the skill on GitHub.** It's at
[github.com/mattpocock/skills/…/skills/productivity/grill-me](https://github.com/mattpocock/skills/tree/v1.3.1/skills/productivity/grill-me).
That link has everything you need:

```
https://github.com/mattpocock/skills/tree/v1.3.1/skills/productivity/grill-me
                   └──── repo ─────┘      └tag─┘ └────── skill folder ──────┘
```

**2. Check its `SKILL.md` for other skills it uses.** grill-me's instructions say to use the `grilling` skill, so you need that one too.

**3. Add one entry to `packages`:**

```json
"packages": [
  {
    "source": "git:github.com/mattpocock/skills@v1.3.1",
    "skills": [
      "skills/productivity/grill-me",
      "skills/productivity/grilling"
    ]
  }
]
```

**4. Run `./setup.sh`, then commit** so the team gets it on their next `./setup.sh`.

**5. Use it.** In pi, type `/skill:grill-me`.

### Other cases

| You want to | Do this |
|---|---|
| Add some skills from a repo | `{ "source": "git:github.com/OWNER/REPO@TAG", "skills": ["path/to/skill", …] }` |
| Add every skill in a repo | `"git:github.com/OWNER/REPO@TAG"` (just the string) |
| Move to a newer version | Change the `@TAG` |
| Remove a skill | Delete its path from `"skills"`, or delete the whole entry |
| Add a skill written here | Create `skills/<name>/SKILL.md` (see [skills/README.md](skills/README.md)) |

Then run `./setup.sh`.

### Rules

- **Always pin** to a version tag (`@v1.3.1` or `@1.3.1`) or a full commit SHA. `setup.sh` refuses anything else, including branches like `@main`, which move. If a repo's tags don't start with `v` or a digit, use the commit SHA.
- **Other people's repos:** prefer the commit SHA. Its owner can move a tag, and your agent follows a skill's instructions. `gh api repos/OWNER/REPO/commits/TAG --jq .sha` prints the SHA for a tag.
- **Repo layout:** pi finds a repo's skills in its `skills/` folder, or wherever the repo's `package.json` points with `"pi": {"skills": [...]}`. Matt's and Anthropic's skill repos both use `skills/`.
- **Removing:** removing an entry removes those skills from every machine. Packages a developer installed themselves aren't touched.
- **Format:** entries use pi's own package format, so they can also bring pi extensions and prompt templates.

## Add a tool

Add a line under `[tools]` in [mise.toml](mise.toml) with an exact version, run `./setup.sh`, then commit. `scripts/test.sh` checks every tool listed there.

| The tool is | Line to add |
|---|---|
| Known to mise (`mise registry NAME` prints its sources) | `NAME = "1.2.3"` |
| Released on GitHub as ready-built binaries | `"github:OWNER/REPO" = "1.2.3"` |
| An npm package | `"npm:PACKAGE" = "1.2.3"` |

Environment variables everyone needs go under `[env]` in the same file.

## Keep up to date

| What happened | Run |
|---|---|
| Someone pushed changes to this repo | `~/agent-kit/setup.sh`. It pulls them first. |
| You edited `pi-settings.json`, `mise.toml` or `skills/` | `./setup.sh`. It doesn't pull while you have uncommitted changes. |
| A skill repo has a new release | Change its `@tag` in `pi-settings.json`, then run `./setup.sh` |
| You want a newer tool | Change its version in `mise.toml`, then run `./setup.sh` (`mise outdated --bump` lists newer versions) |
| The kit needs a newer mise | Raise `min_version` in `mise.toml`. `setup.sh` updates mise on machines with an older one. |

`setup.sh` is always safe to re-run. Versions come from this repo, so don't run `herdr update` or plain `pi update`, which updates pi itself. `pi update --extensions` is fine.

## What's in here

| File | Controls |
|---|---|
| `setup.sh` | Pulls this repo, then installs or updates everything. It has no lists of its own. |
| `mise.toml` | Tools and their versions, the oldest mise that works, and environment variables |
| `pi-settings.json` | pi defaults and skill packages. These keys are reset on every run, and a key deleted here is deleted on every machine; your other pi settings aren't touched. |
| `skills/` | Skills written in this repo |
| `scripts/test.sh` | For maintainers: runs `setup.sh` on a pretend new machine and checks the result |

## Remote agents on a GCP VM

1. Make `ssh devbox` work. Use `gcloud compute config-ssh`, or, for IAP-only VMs, add a `Host devbox` entry with:
   ```
   ProxyCommand gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --zone=ZONE --project=PROJECT
   ```
2. On the VM (`ssh devbox`), follow "Set up" above. Both logins, GitHub and Copilot, work over SSH, and each VM needs them once.
3. Use it in either of two ways:
   - **From your Mac:** run `herdr machine add devbox` once, then `herdr --remote devbox`.
   - **On its own:** SSH in, run `herdr`, start agents and detach. They keep running until the VM reboots.

## Troubleshooting

| Problem | Fix |
|---|---|
| `setup.sh` failed | Accept its offer to open pi. Or, later, run `pi -a @.setup-failure.md` in this folder. |
| `pi` or `herdr` not found after setup | Open a new terminal. |
| setup says "Not pulling the latest kit" | You have uncommitted changes in `~/agent-kit` (`git status` lists them). Commit or discard them, then re-run `./setup.sh`. |
| `herdr --remote` runs a different herdr on the VM | Re-run `~/agent-kit/setup.sh` on the VM. Then `ssh devbox 'command -v herdr'` should print a path in `~/.local/share/mise/shims`. |
| An old `pi` (from npm or Homebrew) runs instead | Make the `mise activate` line the last line of `~/.zshrc`, or uninstall the old one. |
| pi says "The requested model is not supported" | Unset `COPILOT_GITHUB_TOKEN` and use `/login`. pi doesn't handle that variable correctly for Copilot. |
| `gpt-6-luna` isn't available | Your org's Copilot policy hasn't enabled it. Ask the Copilot admin. |
| herdr says the server version differs | When no agents are running: `herdr server stop`, then `herdr`. |
| Downloads fail at the office | `export HTTPS_PROXY=…`, then re-run `./setup.sh`. |

## Why these tools

- **mise** installs every tool from one file, on macOS and Linux, without admin rights.
- **pi's own packages** for skills. We tried Microsoft's APM; it works, but pi can install skills from git by itself, so that's one tool less. Pinned links keep every machine on the same versions.
- **Copilot `/login`** rather than a token: pi sends a token from the environment straight to Copilot, which rejected every request in our test.

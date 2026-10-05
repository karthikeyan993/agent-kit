# How agent-kit works

## Three layers

| Layer | What it is | Configured in | Installed to |
|---|---|---|---|
| **Tools** | [mise](https://mise.jdx.dev) installs herdr, pi, node, gh, ripgrep, fd and jq at exact versions | `config/mise.toml` | `~/.local/share/mise` |
| **Agent** | pi, with team default settings and team skill packages | `config/pi-settings.json`, `config/pi-packages.txt` | `~/.pi/agent` |
| **Workspace** | herdr runs agents in panes, on your Mac or on a VM | Personal (`~/.config/herdr/config.toml`) | herdr's own state |

## What `bootstrap.sh` does

`bootstrap.sh` loads `lib/common.sh` and runs each file in `steps/` in filename order. It then runs `scripts/doctor.sh`. Each step is a short, commented script that does one thing:

| Step | Does | Why |
|---|---|---|
| `00-preflight` | Checks the OS, CPU and `git`/`curl`/`tar` | Fails early with a clear fix, instead of halfway through |
| `10-mise` | Installs mise if it's missing | mise installs everything else |
| `20-tools` | Links `config/mise.toml` into mise's global config, then installs the tools | The tools work in every directory; a `git pull` updates the link target |
| `30-shell` | Adds one `mise activate` line to `~/.zshrc` or `~/.bashrc` | New terminals find the tools |
| `40-github` | Runs `gh auth login` if needed, then `gh auth setup-git` | git can clone private skill repos |
| `50-pi-settings` | Merges `config/pi-settings.json` into pi's settings | Team defaults, without overwriting personal choices |
| `60-pi-packages` | Makes the installed team packages match `config/pi-packages.txt` | Adding, re-pinning and removing skills all work the same way |
| `70-herdr` | Runs `herdr integration install pi` | herdr shows each agent's state and can restore sessions |

Every step can be re-run safely. It either changes nothing or brings the machine back in line with `config/`.

## Team defaults vs personal choices

**Settings.** The team file and personal choices are told apart by remembering what the kit applied last time (the rules are in `lib/settings.jq`):

- A setting nobody touched follows the team file. That includes later changes to the file and settings the team removes.
- A setting the developer changed themselves is kept. `scripts/doctor.sh` lists these as warnings so they stay visible.

**Packages** work the same way. The kit only removes packages it installed itself. Packages a developer installs with `pi install` are never touched.

## Where things live on a machine

| Path | What | Owned by |
|---|---|---|
| `~/agent-kit/` | This repo | The team (via git) |
| `~/.local/bin/mise` | mise | The kit installs it once |
| `~/.config/mise/conf.d/agent-kit.toml` | Symlink to `config/mise.toml` | The kit |
| `~/.local/share/mise/` | Installed tool versions | mise |
| `~/.zshrc` or `~/.bashrc` | One `mise activate` line | The kit adds it once |
| `~/.pi/agent/settings.json` | pi settings: team defaults plus your changes | Shared |
| `~/.pi/agent/auth.json` | Your Copilot login | You. Never commit or share it. |
| `~/.pi/agent/extensions/herdr-agent-state.ts` | herdr's hook into pi | herdr |
| `~/.local/state/agent-kit/` | What the kit applied last time (settings, packages) | The kit |
| `~/.config/herdr/config.toml` | herdr keys and theme | You |

## Laptop and VM

```
  Your Mac                                 GCP VM
  ┌────────────────┐        SSH         ┌──────────────────────────┐
  │  herdr client  │ ─────────────────▶ │  herdr server            │
  └────────────────┘                    │   ├─ pi + team skills ───┼─▶ GitHub Copilot
                                        │   └─ pi + team skills ───┼─▶ GitHub Copilot
                                        └──────────────────────────┘
```

Both machines run the same `bootstrap.sh`, so they have the same pinned versions. herdr's client and server must stay compatible, which is why one herdr version is pinned for everyone. When you detach, agents keep running on the VM.

## Principles

- **One place for team decisions.** Everything team-wide is in `config/`; personal setup stays personal.
- **Pinned, reviewed changes.** Versions change only through PRs that pass `scripts/test-sandbox.sh` on macOS and Linux.
- **Safe to re-run.** Running the bootstrap again is the fix for most problems.
- **No shared secrets.** Each person logs in to GitHub and Copilot with their own account; the repo holds no credentials.

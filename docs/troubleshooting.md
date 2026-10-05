# Troubleshooting

Start with the health check:

```bash
~/agent-kit/scripts/doctor.sh
```

Every FAIL or WARN line ends with its fix. Re-running `./bootstrap.sh` fixes most problems, because it's safe to re-run.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `pi: command not found` right after the bootstrap | Your terminal started before the bootstrap | Open a new terminal |
| doctor: "`pi` comes from …/nvm/…, not mise" | An older pi (npm or Homebrew) comes earlier in `PATH` | Make the `mise activate` line the last line of `~/.zshrc`, or uninstall the old pi: `npm uninstall -g @earendil-works/pi-coding-agent` |
| doctor: "not logged in to GitHub Copilot" | Each machine needs its own login | Run `pi`, type `/login`, choose GitHub Copilot |
| doctor: "default model … is not available to your account" | Your org's Copilot policy hasn't enabled that model | Ask your Copilot admin, or pick another model with `/model` |
| pi: "The requested model is not supported" | Usually a `COPILOT_GITHUB_TOKEN` variable is set, which pi uses in place of `/login` | Remove the variable; see [decisions](decisions.md#copilot-login-not-a-token) |
| doctor: "herdr server runs X but Y is installed" | herdr was upgraded while its server was running | When no agents are running: `herdr server stop`, then `herdr` |
| Bootstrap: download or `mise install` fails at the office | A proxy, TLS inspection, or GitHub rate limits | Export `HTTPS_PROXY` (and your proxy's CA, if needed) and re-run. Log in with `gh auth login` first so downloads are authenticated. |
| Bootstrap: `pi install git:…` fails | No access to the private skill repo | `gh auth login`, check you can open the repo on github.com, then re-run |
| `herdr machine add` offers to install herdr on the VM | It didn't find herdr on the VM's `PATH` in a non-interactive SSH session | Run `./bootstrap.sh` on the VM first. If it still offers, report it; this path hasn't been verified yet. |

## Go back to the team defaults

`scripts/doctor.sh` lists each pi setting where you differ from the team. Delete those keys from `~/.pi/agent/settings.json` and re-run `./bootstrap.sh`; the team values come back.

Don't delete `~/.local/state/agent-kit/`. It's how the kit tells its own settings and packages apart from yours.

## Reinstall the tools

If a tool install looks broken, remove that tool's folder under `~/.local/share/mise/installs/` and re-run `./bootstrap.sh`. Your logins and pi sessions aren't affected.

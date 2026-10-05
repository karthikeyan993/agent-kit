# Notes for coding agents

This repo sets up herdr, pi and team skills on developer Macs and GCP Linux VMs. Read [README.md](README.md) first. The repo is deliberately small; keep it that way.

## Rules

- `scripts/test.sh` is the definition of "works". Run it and show its output before claiming anything works.
- Test in the sandbox first. Run `./setup.sh` against the real home directory only when the user asks.
- Keep versions pinned in `mise.toml`. Never run `herdr update` or `pi update self`.
- Never commit credentials: `~/.pi/agent/auth.json`, tokens, `.env`.
- When behavior changes, update README.md.

## Status

Verified with `scripts/test.sh` (all 18 checks) on macOS 26 arm64 and Ubuntu 24.04 arm64, 2026-10-05. `./setup.sh --update` was also checked by hand.

Not yet verified:

1. A real GitHub Copilot `/login` followed by a prompt on `gpt-6-luna`. The model selection was checked with a dummy token only.
2. Private skill repos. APM should pick up the `gh auth login` automatically, but this is untested.
3. The office network: proxy, TLS inspection, blocked downloads.
4. A GCP VM end to end, with `herdr machine add` and `herdr --remote` from a Mac.
5. Whether herdr's SSH connection finds the mise-installed `herdr` on the VM. If it offers to install its own copy into `~/.local/bin`, it couldn't.

## Your tasks (office laptop)

Do these in order. After each one, update "Status" and commit fixes with a message that says what failed.

1. Ask the user for the GitHub org. Replace `YOUR_ORG` in README.md.
2. Run `scripts/test.sh`. If downloads fail, check for a proxy; `ENV` in the script uses `env -i`, so a needed `HTTPS_PROXY` must be added there.
3. Ask the user for the team's skill links. Add them to `apm.yml`, preferably pinned with `#tag`. Run `scripts/test.sh` again, then commit `apm.yml`.
4. Only with the user's go-ahead:
   - Run `./setup.sh`. The user does the `/login` themselves.
   - Run `pi -p 'Reply with OK'`.
   - Commit `apm.lock.yaml`.
5. GCP VM, with the user. They create the VM and its SSH access; don't create cloud resources yourself.
   - On the VM, run `scripts/test.sh`, then `./setup.sh`.
   - From the Mac, run `herdr machine add` and then `herdr --remote`.
   - Check item 5 above.
6. Report to the user what passed, what failed, and what you changed.

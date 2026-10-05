# Notes for coding agents

This repo sets up herdr, pi and team skills on developer Macs and GCP Linux VMs. Read [README.md](README.md) first. The repo is deliberately small; keep it that way.

## Rules

- `scripts/test.sh` is the definition of "works". Run it and show its output before claiming anything works.
- Test in the sandbox first. Run `./setup.sh` against the real home directory only when the user asks.
- Keep versions pinned in `mise.toml`. Never run `herdr update` or `pi update self`.
- Never commit credentials: `~/.pi/agent/auth.json`, tokens, `.env`.
- When behavior changes, update README.md.

## When setup.sh fails

`setup.sh` opens you with `.setup-failure.md`, which names the step and command that failed. Every machine must end up exactly as `setup.sh` makes it, so your job is to clear what blocked the script, not to do its work another way.

1. Re-run `./setup.sh` to see the full error. It's safe to re-run. Your shell has no terminal, so its login steps are skipped; if a login is the problem, ask the user to run `gh auth login` or `/login`.
2. Fix the cause on this machine, for example a proxy setting, a missing system package, or a broken install folder. Ask the user before running `sudo`, editing shell startup files, or deleting anything outside this repo.
3. Don't edit `mise.toml`, `apm.yml` or `pi-settings.json` to get past an error, and don't install the tools some other way.
4. You're done when `./setup.sh` finishes without errors. Tell the user what was wrong and what you changed.
5. If other machines would hit the same problem, propose the fix to `setup.sh` itself and run `scripts/test.sh`. Leave committing and pushing to the user.

## Status

Verified with `scripts/test.sh` (all 22 checks, including a failed setup that points to pi) on macOS 26 arm64 and Ubuntu 24.04 arm64, 2026-10-05. Checked by hand: `./setup.sh --update`, and in a terminal the Copilot login hand-off and both answers to "Open pi to fix it?" (pi opened with the failure note, `AGENTS.md` and the skills loaded).

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

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
3. Don't edit `mise.toml`, `pi-settings.json` or `skills/` to get past an error, and don't install the tools or skills some other way.
4. You're done when `./setup.sh` finishes without errors. Tell the user what was wrong and what you changed.
5. If other machines would hit the same problem, propose the fix to `setup.sh` itself and run `scripts/test.sh`. Leave committing and pushing to the user.

## Status

Verified with `scripts/test.sh` (27 checks: install; mise at least `min_version`, and an older one updated; every tool in `mise.toml`; new terminals and one-command shells find the tools; team adds and removes skills and a setting; personal package and setting kept; unpinned and `@main` links refused; broken link hands off to pi; setup pulls a pushed fix) on macOS 26 arm64, 2026-10-05. The earlier 22-check version also passed on Ubuntu 24.04 arm64; this version hasn't been run there yet. Checked by hand: the Copilot login hand-off and both answers to "Open pi to fix it?" (earlier version), zsh shell setup in the sandbox, and `gh repo clone` over HTTPS for a private repo with no git credentials set up (the README's Set up steps).

Not yet verified:

1. A real GitHub Copilot `/login` followed by a prompt on `gpt-6-luna`. The model selection was checked with a dummy token only.
2. Private skill repos. pi clones them with git, which uses the `gh auth login` through `gh auth setup-git`. This is untested.
3. The office network: proxy, TLS inspection, blocked downloads.
4. A GCP VM end to end, with `herdr machine add` and `herdr --remote` from a Mac.
5. Whether herdr's SSH connection finds the mise-installed `herdr` on the VM. herdr runs `command -v herdr` in the SSH shell; `setup.sh` now puts mise's shims at the top of `.bashrc` for that, which `scripts/test.sh` simulates. If `herdr machine add` still installs its own copy into `~/.local/bin`, it didn't work.
6. The README's Set up steps on a brand-new Mac, including the `gh auth login` in a browser.

## Your tasks (office laptop)

Do these in order. After each one, update "Status" and commit fixes with a message that says what failed.

1. Ask the user for the GitHub org. Replace `YOUR_ORG` in README.md.
2. Run `scripts/test.sh`. If downloads fail, check for a proxy: set `HTTPS_PROXY` and `NO_PROXY` (and `SSL_CERT_FILE` or `NODE_EXTRA_CA_CERTS` for TLS inspection) in your shell. The script passes them into its sandbox.
3. Ask the user for the team's skill repos. Add them to `packages` in `pi-settings.json`, pinned with `@tag` or `@commit` (README.md shows the format). Each repo needs a `skills/` folder or a `package.json` with `"pi": {"skills": [...]}`; if one doesn't have either, tell the user. Run `scripts/test.sh` again, then commit.
4. Only with the user's go-ahead:
   - Run `./setup.sh`. The user does the `/login` themselves.
   - Run `pi -p 'Reply with OK'`.
5. GCP VM, with the user. They create the VM and its SSH access; don't create cloud resources yourself.
   - On the VM, run `scripts/test.sh`, then `./setup.sh`.
   - From the Mac, run `herdr machine add` and then `herdr --remote`.
   - Check items 5 and 6 above.
6. Report to the user what passed, what failed, and what you changed.

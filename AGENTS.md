# agent-kit: notes for coding agents

This repo sets up our team's agent tooling (herdr, pi, team skills) on developer Macs and on GCP Linux VMs. Read [README.md](README.md) first; it's the user-facing doc and must stay accurate.

## Files

- `mise.toml`: pinned tool versions. bootstrap symlinks it into `~/.config/mise/conf.d/agent-kit.toml`.
- `bootstrap.sh`: idempotent setup, run by humans. It must keep working with `</dev/null` (no TTY) for tests.
- `pi-settings.json`: team pi defaults. They're deep-merged under the user's settings, so the user's own keys win.
- `pi-packages.txt`: team pi packages (skills/extensions), one source per line, pinned to a tag.
- `scripts/test-sandbox.sh`: fresh-machine test in a throwaway `HOME`. This is the definition of "works".

## Rules

- Test with `scripts/test-sandbox.sh` before changing the real `~`. Don't run `bootstrap.sh` against the real home until the sandbox passes.
- Keep versions pinned. Bump them in `mise.toml`, never with `herdr update` or `pi update self`.
- Never commit credentials: `~/.pi/agent/auth.json`, tokens, `.env`.
- Don't claim something works unless a command you ran shows it. Record what you verified in "Status" below.

## Status

Verified with `scripts/test-sandbox.sh` (fresh `HOME`, bare `PATH`, two runs):

| Platform | Result |
|---|---|
| macOS 26 arm64 (personal laptop) | All checks pass (2026-10-05) |
| Ubuntu 24.04 arm64 (Lima VM, no GitHub token) | All checks pass (2026-10-05) |

Not yet verified:

- A real GitHub Copilot `/login` followed by a prompt on `gpt-6-luna` at `xhigh`. Only the startup selection was checked, using a dummy token.
- Installing a private git repo from `pi-packages.txt`. The file has no real entries yet.
- The office network, which may have a proxy, TLS inspection, or blocked `mise.run` or GitHub release downloads.
- A GCP VM end to end, including `herdr machine add` and `herdr --remote` from a Mac.
- Whether herdr's SSH bootstrap finds the mise-installed `herdr` in a non-interactive SSH session. If it doesn't, it offers to install its own copy into `~/.local/bin`.

## Your tasks (office laptop)

Work through these in order. After each one, update "Status", and commit any fixes with a message that says what failed.

1. **Sandbox on this Mac.** Run `scripts/test-sandbox.sh`.
   - If a download fails, find out whether the cause is the network. On a proxy, `HTTPS_PROXY` must reach the sandbox. `run()` in the script uses `env -i`, so pass it through there if needed.
2. **Team skills.** Ask the user for the GitHub repo(s) that hold the team skills. Add each one to `pi-packages.txt` as `git:github.com/ORG/REPO@TAG`.
   - pi finds skills in a `skills/` directory, or wherever a `package.json` points with `"pi": {"skills": [...]}`. If a repo has neither, propose adding a `package.json` to that repo; don't restructure it.
   - Re-run the sandbox test and confirm the expected skill names are listed.
3. **Real install on this Mac.** Only after step 2 passes, and only with the user's go-ahead:
   - Run `./bootstrap.sh`. The user does the `/login` for GitHub Copilot themselves.
   - In a new shell, confirm `which pi herdr` point into `~/.local/share/mise`, not nvm or Homebrew.
   - Run `pi --list-models gpt-6-luna`.
   - Run `pi -p 'Reply with OK'` to confirm Copilot actually answers. The sandbox test already checks that the model and thinking level are selected correctly.
   - If the org's Copilot policy hides `gpt-6-luna`, tell the user. Don't silently switch the default.
4. **GCP VM.** Follow the README's "Remote devbox (GCP)" section with the user.
   - The user creates or chooses the VM and its SSH access. Don't create cloud resources yourself.
   - On the VM, run the sandbox test first, then the bootstrap.
   - From the Mac, run `herdr machine add` and then `herdr --remote`.
   - Check the last unverified item: on the VM, see whether `~/.local/bin/herdr` appeared. If it did, herdr couldn't see the mise one. Fix that in `bootstrap.sh`, for example with a shims `PATH` line in `~/.profile` or `~/.zshenv`, and re-test.
5. **Report.** Summarize for the user what passed, what failed, what you changed, and anything still open.

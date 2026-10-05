# agent-kit: notes for coding agents

This repo sets up the team's agent tooling (herdr, pi, team skills) on developer Macs and GCP Linux VMs. Read [README.md](README.md) and [docs/architecture.md](docs/architecture.md) first.

## Layout

- `config/` is where team decisions live: tool versions, pi defaults, skill packages. Most changes belong here.
- `steps/NN-name.sh` holds one setup step each. `bootstrap.sh` sources them in order with `set -euo pipefail`.
- `lib/common.sh` has the shared helpers. `lib/settings.jq` has the rules for merging pi settings.
- `scripts/doctor.sh` is the read-only health check. `scripts/test-sandbox.sh` is the fresh-machine test. `scripts/lint.sh` runs the static checks.

## Rules

- **"Works" means the checks pass.** Run `scripts/lint.sh` and `scripts/test-sandbox.sh` and show their output. Never claim something works without that.
- **Test in the sandbox before touching the real `~`.** Only run `./bootstrap.sh` against the real home directory when the user asks.
- **Keep steps safe to re-run.** Write steps as `if` blocks, not `cond && action`. With `set -e`, a false condition at the end of a sourced step file aborts the whole bootstrap.
- **Keep versions pinned in `config/mise.toml`.** Never run `herdr update` or `pi update self`.
- **Never commit credentials:** `~/.pi/agent/auth.json`, tokens, `.env`.
- **Keep docs and the changelog current.** If behavior changes, update the matching doc in `docs/` and add a `CHANGELOG.md` entry.

## Status

Verified with `scripts/test-sandbox.sh`:

| Platform | Result |
|---|---|
| macOS 26 arm64 | All checks pass (2026-10-05) |
| Ubuntu 24.04 arm64 (Lima VM, no GitHub token) | All checks pass (2026-10-05) |

Not yet verified:

1. A real GitHub Copilot `/login` followed by a prompt on `gpt-6-luna`. Only the model and thinking-level selection were checked, using a dummy token.
2. Installing a private git repo listed in `config/pi-packages.txt`. The file has no entries yet.
3. The office network: proxy, TLS inspection, blocked downloads.
4. A GCP VM end to end, with `herdr machine add` and `herdr --remote` from a Mac.
5. Whether herdr's SSH setup finds the mise-installed `herdr` in a non-interactive SSH session.
6. The CI workflow on GitHub Actions. It was linted with actionlint but hasn't run yet.
7. A fine-grained `github_pat_` token in `COPILOT_GITHUB_TOKEN`, instead of `/login` (optional). See docs/decisions.md.

## Your tasks (office laptop)

Do these in order. After each one, update "Status", and commit any fixes with a message that says what failed.

1. **Placeholders.** Ask the user for the GitHub org and owning team. Replace `YOUR_ORG` and `YOUR_TEAM` across the repo (`grep -rn 'YOUR_' .`).
2. **Sandbox.** Run `scripts/test-sandbox.sh` on this Mac.
   - If downloads fail, check whether the office network is the cause. `run()` in the script uses `env -i`, so a needed `HTTPS_PROXY` must be added to `SBX_ENV`.
3. **Team skills.** Ask the user for the skill repos. Add each one to `config/pi-packages.txt` as `git:github.com/ORG/REPO@TAG`.
   - pi finds skills in `skills/`, or via `package.json` → `"pi": {"skills": [...]}`. If a repo has neither, propose adding a `package.json` there; don't restructure the repo.
   - Re-run the sandbox and confirm the expected skill names are listed.
4. **Real install.** Only with the user's go-ahead:
   - Run `./bootstrap.sh`. The user does the Copilot `/login` themselves.
   - Run `scripts/doctor.sh`. It must show no FAIL.
   - Run `pi -p 'Reply with OK'` to confirm Copilot answers.
   - If the org's Copilot policy hides `gpt-6-luna`, tell the user. Don't silently change the default.
5. **CI.** After the user pushes the repo, check the workflow run. If the skill repos are private, ask the user to add the `SKILLS_READ_TOKEN` secret (docs/maintaining.md).
6. **GCP VM.** Follow docs/remote-gcp.md with the user.
   - The user creates the VM and its SSH access. Don't create cloud resources yourself.
   - On the VM, run the sandbox test, then the bootstrap.
   - From the Mac, run `herdr machine add` and then `herdr --remote`.
   - For item 5 in "Not yet verified", check whether `~/.local/bin/herdr` appeared on the VM. If it did, herdr couldn't see the mise one. Fix that in a step (for example, a shims `PATH` line in `~/.profile`), re-test, and update docs/troubleshooting.md.
7. **Report.** Tell the user what passed, what failed, what you changed, and what's still open.

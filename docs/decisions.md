# Decisions

Short records of why agent-kit is built the way it is. Add a section when you make a choice someone might later question.

## mise for tools, not Nix or APM (2026-10)

**Decision:** install tools with mise, pinned in `config/mise.toml`.

**Why:**

- mise supports every tool directly. herdr is in its registry, and pi publishes standalone release binaries that mise installs with `github:earendil-works/pi`.
- One file works on macOS and Linux, with no root access and no `/nix` store.
- **Nix** would give stronger reproducibility, but pi isn't packaged officially in nixpkgs, and pi installs its own packages with npm at runtime, so the guarantee ends at the agent. Meanwhile the team would pay Nix's learning cost. Revisit Nix if we want prebuilt, identical VM images.
- **Microsoft APM** only covers skills and MCP servers, not tools. pi's own packages already handle skills: `pi install git:…@tag`.

## Pin ripgrep and fd (2026-10)

If pi can't find `rg` or `fd`, it downloads the latest release from GitHub the first time it needs them. That download is unpinned, and it fails behind office proxies. Pinning both in mise avoids the surprise.

## Copilot login, not a token (2026-10)

**Decision:** each person runs `/login` → GitHub Copilot in pi, once per machine.

**Why:**

- pi also accepts a `COPILOT_GITHUB_TOKEN` environment variable, but it sends that token straight to the individual-plan Copilot endpoint. It skips the token exchange and the account-specific endpoint lookup that `/login` does.
- In a test with a `gh` login token, Copilot accepted the token, listed the account's models, and still rejected every chat request with "The requested model is not supported".
- `/login` handles Business and Enterprise seats properly, refreshes itself, and takes about a minute.

**Not yet tested:** a fine-grained `github_pat_` token with the "Copilot Requests" permission. If someone tests it and it works, the bootstrap could read a token and skip `/login`.

## Developers' own settings win (2026-10)

**Decision:** team pi defaults never overwrite a value a developer chose. A value counts as theirs only if it differs from what the kit applied last time, which is recorded in `~/.local/state/agent-kit/`.

**Why:** without that record, the first value the kit writes would look like a personal choice forever, and later changes to the team defaults would never reach anyone. See `lib/settings.jq`.

## Bash, not a configuration management tool (2026-10)

The setup is eight short steps on machines we don't administer centrally. Plain bash runs everywhere with nothing to install first, and anyone can read it. Revisit this if the setup grows past "a page of steps".

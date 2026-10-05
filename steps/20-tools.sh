# shellcheck shell=bash
# Step 2: install the pinned tools from config/mise.toml for this user.

# A symlink, not a copy, so `git pull` + re-running picks up version bumps.
MISE_CONF_D="${MISE_CONFIG_DIR:-$HOME/.config/mise}/conf.d"
mkdir -p "$MISE_CONF_D"
ln -sfn "$CONFIG_DIR/mise.toml" "$MISE_CONF_D/agent-kit.toml"
mise trust --quiet "$CONFIG_DIR/mise.toml"

# Authenticated GitHub downloads avoid rate limits on shared office IPs.
if [ -z "${MISE_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}" ] && command -v gh >/dev/null 2>&1; then
  MISE_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
  if [ -n "$MISE_GITHUB_TOKEN" ]; then export MISE_GITHUB_TOKEN; else unset MISE_GITHUB_TOKEN; fi
fi

say "Installing tools from config/mise.toml"
mise install --yes

# Put the tools on PATH for the remaining steps.
eval "$(mise activate bash --shims)"

#!/usr/bin/env bash
# One-shot setup for a laptop or a remote devbox (macOS or Linux).
# Safe to re-run: every step is idempotent. Re-run after `git pull` to pick up
# new tool versions or packages.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE_CONF_DIR="${MISE_CONFIG_DIR:-$HOME/.config/mise}/conf.d"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# 1. mise
if ! command -v mise >/dev/null 2>&1; then
  say "Installing mise"
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Team toolchain, global for this user. Symlink so `git pull` updates it.
say "Linking team toolchain into $MISE_CONF_DIR"
mkdir -p "$MISE_CONF_DIR"
ln -sfn "$KIT_DIR/mise.toml" "$MISE_CONF_DIR/agent-kit.toml"
mise trust --quiet "$KIT_DIR/mise.toml"

# Authenticated GitHub API calls avoid rate limits on shared office IPs.
if [ -z "${MISE_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}" ] && command -v gh >/dev/null 2>&1; then
  MISE_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
  [ -n "$MISE_GITHUB_TOKEN" ] && export MISE_GITHUB_TOKEN || unset MISE_GITHUB_TOKEN
fi

say "Installing tools (herdr, pi, node, ...)"
mise install --yes
eval "$(mise activate bash --shims)"

# 3. Shell activation for interactive shells.
add_line() {
  local file="$1" line="$2"
  [ -f "$file" ] && grep -qF "$line" "$file" && return 0
  printf '\n# added by agent-kit bootstrap\n%s\n' "$line" >>"$file"
  say "Added mise activation to $file"
}
case "$(basename "${SHELL:-bash}")" in
  zsh) add_line "$HOME/.zshrc" 'eval "$(mise activate zsh)"' ;;
  bash) add_line "$HOME/.bashrc" 'eval "$(mise activate bash)"' ;;
  *) warn "Unknown shell $SHELL: add mise activation yourself (https://mise.jdx.dev/getting-started.html)" ;;
esac

# 4. Let git (and therefore `pi install git:...`) read private GitHub repos.
if ! gh auth status >/dev/null 2>&1 && [ -t 0 ]; then
  say "Logging in to GitHub (needed for private skill repos)"
  gh auth login --hostname github.com --git-protocol https --web
fi
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git
else
  warn "gh is not logged in; private package repos will fail. Run: gh auth login && ./bootstrap.sh"
fi

# 5. Team pi defaults (GitHub Copilot provider). Keys the developer already
# set in their own settings.json win, so re-running never clobbers choices.
PI_SETTINGS="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"
mkdir -p "$(dirname "$PI_SETTINGS")"
[ -f "$PI_SETTINGS" ] || echo '{}' >"$PI_SETTINGS"
jq -s '.[0] * .[1]' "$KIT_DIR/pi-settings.json" "$PI_SETTINGS" >"$PI_SETTINGS.tmp"
mv "$PI_SETTINGS.tmp" "$PI_SETTINGS"

# 6. Team pi packages: skills, extensions, prompts.
while IFS= read -r src; do
  src="${src%%#*}"
  src="$(printf '%s' "$src" | tr -d '[:space:]')"
  [ -z "$src" ] && continue
  say "pi install $src"
  pi install "$src"
done <"$KIT_DIR/pi-packages.txt"

# 7. herdr <-> pi integration (agent state in pane borders, session restore).
say "Installing herdr integration for pi"
herdr integration install pi
if command -v claude >/dev/null 2>&1; then
  herdr integration install claude
fi

printf '\nDone. Next:\n  1. Open a new terminal (or: exec $SHELL)\n'
if pi auth check --provider github-copilot >/dev/null 2>&1; then
  echo "  2. GitHub Copilot login: OK"
else
  cat <<'EOF'
  2. Sign in to GitHub Copilot (once per machine):
       run `pi`, type /login, pick "GitHub Copilot",
       leave the Enterprise domain blank (unless we're on *.ghe.com),
       then enter the device code at github.com/login/device
EOF
fi
echo "  3. Run \`herdr\` to start a workspace"

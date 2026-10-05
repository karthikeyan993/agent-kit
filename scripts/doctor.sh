#!/usr/bin/env bash
# Read-only health check for this machine. Safe to run at any time; paste
# its output when asking for help. Exits 1 if anything FAILs.
#
# Usage: scripts/doctor.sh
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$KIT_DIR/lib/common.sh"
export PATH="$HOME/.local/bin:$PATH" # where the mise installer puts mise

kit_version="$(git -C "$KIT_DIR" describe --always --dirty 2>/dev/null || echo unknown)"
printf 'agent-kit doctor: kit %s on %s/%s\n' "$kit_version" "$(uname -s)" "$(uname -m)"

section "Tools"
path_fix="open a new terminal; if it persists, make the mise line the last line of your shell rc"
if command -v mise >/dev/null 2>&1; then
  pass "mise $(mise --version 2>/dev/null | awk '{print $1}')"
  missing="$(cd / && mise ls --missing 2>/dev/null)"
  if [ -z "$missing" ]; then
    pass "all versions pinned in config/mise.toml are installed"
  else
    fail "pinned versions not installed (fix: ./bootstrap.sh):"
    printf '%s\n' "$missing" | sed 's/^/         /'
  fi
else
  fail "mise not found (fix: ./bootstrap.sh)"
  path_fix="./bootstrap.sh"
fi
for cmd in herdr pi node gh rg fd jq; do
  path="$(command -v "$cmd" 2>/dev/null || true)"
  case "$path" in
    "") fail "$cmd not on PATH (fix: $path_fix)" ;;
    */mise/*) pass "$cmd: $("$cmd" --version 2>&1 | head -1)" ;;
    *) fail "$cmd comes from $path, not mise (fix: $path_fix)" ;;
  esac
done

section "pi"
settings="$PI_AGENT_DIR/settings.json"
if [ ! -f "$settings" ]; then
  fail "no pi settings at $settings (fix: ./bootstrap.sh)"
else
  overrides="$(jq -r -L "$KIT_DIR/lib" --slurpfile team "$CONFIG_DIR/pi-settings.json" \
    'include "settings"; overrides($team[0])' "$settings" 2>/dev/null)"
  if [ -z "$overrides" ]; then
    pass "team defaults from config/pi-settings.json applied"
  else
    caution "your settings override team defaults (allowed):"
    printf '%s\n' "$overrides" | sed 's/^/         /'
  fi

  provider="$(jq -r '.defaultProvider // empty' "$settings")"
  model="$(jq -r '.defaultModel // empty' "$settings")"
  if [ -n "$provider" ] && pi auth check --provider "$provider" >/dev/null 2>&1; then
    pass "logged in to $provider"
    if pi --list-models "$model" 2>/dev/null |
      awk -v p="$provider" -v m="$model" '$1 == p && $2 == m { found = 1 } END { exit !found }'; then
      pass "default model $provider/$model is available to your account"
    else
      fail "default model $provider/$model is not available to your account (fix: ask your Copilot admin to enable it, or pick another model with /model in pi)"
    fi
  elif [ "$provider" = github-copilot ]; then
    fail "not logged in to GitHub Copilot (fix: run pi, type /login, choose GitHub Copilot; once per machine)"
  else
    fail "not logged in to ${provider:-a provider} (fix: run pi, type /login)"
  fi
fi

installed="$(pi list 2>/dev/null || true)"
packages="$(team_packages)"
if [ -z "$packages" ]; then
  caution "config/pi-packages.txt lists no packages yet"
fi
while IFS= read -r src; do
  [ -z "$src" ] && continue
  # pi list shows local paths normalized, and git/npm sources without the ref.
  case "$src" in
    /*) id="$(cd "$src" 2>/dev/null && pwd || printf '%s' "$src")" ;;
    *) id="$(printf '%s' "$src" | sed -E 's#^(git|npm):##; s#^(https?|ssh)://##; s#^git@([^:]+):#\1/#; s#@[^@/]*$##; s#\.git$##')" ;;
  esac
  if printf '%s\n' "$installed" | grep -qF "$id"; then
    pass "package $src"
  else
    fail "package $src not installed (fix: ./bootstrap.sh)"
  fi
done <<<"$packages"

section "herdr"
integrations="$(herdr integration status 2>&1 || true)"
if printf '%s\n' "$integrations" | grep -q '^pi: current'; then
  pass "pi integration installed"
else
  fail "pi integration: $(printf '%s\n' "$integrations" | grep '^pi:' || echo missing) (fix: ./bootstrap.sh)"
fi
status="$(herdr status 2>&1 || true)"
client="$(printf '%s\n' "$status" | awk '/^client:/ { s = 1 } s && /version:/ { print $2; exit }')"
server_state="$(printf '%s\n' "$status" | awk '/^server:/ { s = 1 } s && /status:/ { print $2; exit }')"
server="$(printf '%s\n' "$status" | awk '/^server:/ { s = 1 } s && /version:/ { print $2; exit }')"
if [ "$server_state" != running ]; then
  pass "herdr server not running (it starts with \`herdr\`)"
elif [ "$server" = "$client" ]; then
  pass "herdr server matches the installed version ($client)"
else
  caution "herdr server runs $server but $client is installed (fix, when no agents are running: herdr server stop, then herdr)"
fi

section "GitHub"
if gh auth status >/dev/null 2>&1; then
  pass "gh is logged in"
else
  caution "gh is not logged in; private skill repos can't install (fix: gh auth login)"
fi

section "Shell"
case "$(basename "${SHELL:-bash}")" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
  *) rc="" ;;
esac
if [ -n "$rc" ] && grep -qF 'mise activate' "$rc" 2>/dev/null; then
  pass "mise is activated in $rc"
else
  caution "mise activation not found in your shell rc (fix: ./bootstrap.sh)"
fi

printf '\n%s passed, %s warnings, %s failed\n' "$PASSED" "$WARNED" "$FAILED"
[ "$FAILED" -eq 0 ]

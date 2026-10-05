#!/usr/bin/env bash
# Install or update everything on this machine: tools, skills, pi defaults.
#
#   ./setup.sh            apply this repo to this machine (safe to re-run)
#   ./setup.sh --update   also move skills to the newest versions their links
#                         allow (rewrites apm.lock.yaml; commit it afterwards)
#
# If a step fails, it offers to open pi to diagnose and fix it.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
KIT_DIR="$PWD"

step="checking this machine"
say() { step="$*"; printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
# A person is at the keyboard (and this isn't pi itself running setup.sh).
interactive() { [ -t 0 ] && [ -z "${PI_SESSION_ID:-}${PI_PROVIDER:-}" ]; }

# Fallback: when a step fails, describe it in .setup-failure.md and hand it
# to pi. pi fixes whatever blocked this script, then re-runs it, so every
# machine still ends up the way this script makes it (see AGENTS.md).
on_failure() {
  local status=$? command=$BASH_COMMAND answer
  trap - ERR
  set +e
  {
    echo "# setup.sh failed"
    echo
    echo "- Step: $step"
    echo "- Command: \`$command\` (exit code $status)"
    echo "- Machine: $(uname -s) $(uname -m), shell ${SHELL:-unknown}"
    echo "- Kit version: $(git -C "$KIT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo
    echo "Follow \"When setup.sh fails\" in AGENTS.md."
  } >"$KIT_DIR/.setup-failure.md"
  echo >&2
  warn "Setup failed while: $step"
  if command -v mise >/dev/null 2>&1; then eval "$(mise activate bash --shims 2>/dev/null)"; fi
  if ! command -v pi >/dev/null 2>&1; then
    warn "pi isn't installed yet, so it can't help. Fix the error above, then re-run ./setup.sh."
  elif ! pi auth check --provider github-copilot >/dev/null 2>&1; then
    warn "pi can fix this once you're logged in: run pi, type /login, choose GitHub Copilot, type /quit."
    warn "Then run: cd $KIT_DIR && pi -a @.setup-failure.md"
  elif interactive; then
    printf 'Open pi to diagnose and fix it? [Y/n] '
    read -r answer
    case "$answer" in
      [nN]*) warn "To do it later: cd $KIT_DIR && pi -a @.setup-failure.md" ;;
      *) exec pi -a @.setup-failure.md "Fix this failed setup." ;;
    esac
  else
    warn "To let pi fix it: cd $KIT_DIR && pi -a @.setup-failure.md"
  fi
  exit "$status"
}
trap on_failure ERR

update=""
case "${1:-}" in
  "") ;;
  --update) update=1 ;;
  -h | --help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "Unknown option: $1 (see ./setup.sh --help)" ;;
esac

# 1. Machine check
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64 | Darwin/x86_64 | Linux/x86_64 | Linux/aarch64) ;;
  *) die "Unsupported platform: $(uname -s)/$(uname -m)" ;;
esac
for cmd in curl git tar; do
  command -v "$cmd" >/dev/null 2>&1 ||
    die "Missing $cmd. macOS: xcode-select --install. Debian/Ubuntu: sudo apt-get install -y $cmd"
done

# 2. Tools from mise.toml. The symlink makes them work in every directory
#    and picks up changes after `git pull`.
export PATH="$HOME/.local/bin:$PATH"
if ! command -v mise >/dev/null 2>&1; then
  say "Installing mise"
  curl -fsSL https://mise.run | sh
fi
mise_conf_d="${MISE_CONFIG_DIR:-$HOME/.config/mise}/conf.d"
mkdir -p "$mise_conf_d"
ln -sfn "$KIT_DIR/mise.toml" "$mise_conf_d/agent-kit.toml"
mise trust --quiet "$KIT_DIR/mise.toml"
if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  MISE_GITHUB_TOKEN="$(gh auth token)" # avoids GitHub rate limits on shared office IPs
  export MISE_GITHUB_TOKEN
fi
say "Installing tools"
mise install --yes
eval "$(mise activate bash --shims)"

# Make new terminals find the tools.
# shellcheck disable=SC2016
case "$(basename "${SHELL:-bash}")" in
  zsh) rc="$HOME/.zshrc" line='eval "$(mise activate zsh)"' ;;
  bash) rc="$HOME/.bashrc" line='eval "$(mise activate bash)"' ;;
  *) rc="" line="" ;;
esac
if [ -z "$rc" ]; then
  warn "Unknown shell $SHELL: add mise to it yourself (https://mise.jdx.dev/getting-started.html)"
elif ! grep -qF "$line" "$rc" 2>/dev/null; then
  printf '\n# added by agent-kit setup.sh\n%s\n' "$line" >>"$rc"
  say "Added mise to $rc"
fi

# 3. Logins. GitHub, so private skill repos can be fetched. GitHub Copilot in
#    pi, so pi works (and can fix a failed step) from here on.
if ! gh auth status >/dev/null 2>&1; then
  if interactive; then
    say "Logging in to GitHub"
    gh auth login --hostname github.com --git-protocol https --web
  else
    warn "Not logged in to GitHub; private skills will fail. Fix: gh auth login, then ./setup.sh"
  fi
fi
if ! pi auth check --provider github-copilot >/dev/null 2>&1 && interactive; then
  say "Logging in to GitHub Copilot"
  echo "    pi opens next: type /login, choose GitHub Copilot (leave the Enterprise"
  echo "    domain blank unless you use *.ghe.com), then type /quit to continue."
  printf '    Press Enter to open pi. '
  read -r _
  (cd "$HOME" && pi --no-session) || true
fi

# 4. Skills from apm.yml, into .agents/skills/. Deleted lines are removed.
say "Installing skills"
if [ -n "$update" ]; then
  apm update --yes
fi
apm install
apm prune

# 5. pi defaults from pi-settings.json. Those keys are set to the team value;
#    every other pi setting is left alone. Also points pi at the skills.
settings="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"
mkdir -p "$(dirname "$settings")"
if [ ! -f "$settings" ]; then echo '{}' >"$settings"; fi
jq --slurpfile team pi-settings.json --arg skills "$KIT_DIR/.agents/skills" \
  '. * $team[0] | .skills = ((.skills // []) - [$skills] + [$skills])' \
  "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"

# 6. herdr integration: herdr shows each pi pane's state and restores sessions.
herdr integration install pi

# Summary
rm -f .setup-failure.md
skills=0
if [ -d .agents/skills ]; then
  skills="$(find .agents/skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
fi
echo
say "Done: herdr $(herdr --version | awk '{print $2}'), pi $(pi --version), skills installed: $skills"
if pi auth check --provider github-copilot >/dev/null 2>&1; then
  echo "    GitHub Copilot: logged in."
else
  echo "    Next (once per machine): run pi, type /login, choose GitHub Copilot."
  echo "    Leave the Enterprise domain blank unless you use *.ghe.com."
fi
echo "    Open a new terminal to use the tools."

#!/usr/bin/env bash
# Install or update everything on this machine: tools, skills, pi defaults.
#
#   ./setup.sh      pull the team's latest kit and apply it (safe to re-run)
#
# What gets installed is declared in mise.toml (tools), pi-settings.json
# (pi defaults and skill packages) and skills/ (skills written here).
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

case "${1:-}" in
  "") ;;
  -h | --help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$KIT_DIR/setup.sh"; exit 0 ;;
  *) die "Unknown option: $1 (see ./setup.sh --help)" ;;
esac

# 1. The team's latest kit, so this machine ends up like everyone else's.
#    Skipped while you have local changes here (you're editing the kit).
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  if [ -n "$(git status --porcelain)" ]; then
    warn "Not pulling the latest kit: $KIT_DIR has local changes. Applying it as it is."
  else
    say "Updating agent-kit"
    before="$(git rev-parse HEAD)"
    if ! GIT_TERMINAL_PROMPT=0 git pull --ff-only --quiet; then
      warn "Couldn't pull the latest kit. Applying the copy you have."
    elif [ "$(git rev-parse HEAD)" != "$before" ]; then
      exec bash "$KIT_DIR/setup.sh" "$@" # the new version of this script
    fi
  fi
fi

# 2. Machine check
step="checking this machine"
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64 | Darwin/x86_64 | Linux/x86_64 | Linux/aarch64) ;;
  *) die "Unsupported platform: $(uname -s)/$(uname -m)" ;;
esac
for cmd in curl git tar; do
  command -v "$cmd" >/dev/null 2>&1 ||
    die "Missing $cmd. macOS: xcode-select --install. Debian/Ubuntu: sudo apt-get install -y $cmd"
done

# 3. mise, in ~/.local/bin, at least the min_version in mise.toml. The
#    symlink makes the tools work in every directory and picks up changes
#    after a pull.
export PATH="$HOME/.local/bin:$PATH"
if [ ! -x "$HOME/.local/bin/mise" ]; then
  say "Installing mise"
  curl -fsSL https://mise.run | MISE_INSTALL_HELP=0 sh
fi
min_mise="$(sed -n 's/^min_version *= *"\(.*\)"/\1/p' mise.toml)"
installed_mise="$("$HOME/.local/bin/mise" --version)"
installed_mise="${installed_mise%% *}"
if [ -n "$min_mise" ] &&
  [ "$(printf '%s\n' "$min_mise" "$installed_mise" | sort -V | sed -n 1p)" != "$min_mise" ]; then
  say "Updating mise $installed_mise to $min_mise"
  "$HOME/.local/bin/mise" self-update --yes --no-plugins "$min_mise"
fi
mise_conf_d="${MISE_CONFIG_DIR:-$HOME/.config/mise}/conf.d"
mkdir -p "$mise_conf_d"
ln -sfn "$KIT_DIR/mise.toml" "$mise_conf_d/agent-kit.toml"
mise trust --quiet "$KIT_DIR/mise.toml"

# 4. GitHub, before the other tools: private skill repos need the login, and
#    mise uses the token when it has to fall back to GitHub's API (it can't
#    read a token gh keeps in the macOS keychain, so it's passed on here).
say "Installing gh"
mise install --yes gh
eval "$(mise activate bash --shims)"
if ! gh auth status >/dev/null 2>&1; then
  if interactive; then
    say "Logging in to GitHub"
    gh auth login --hostname github.com --git-protocol https --web
  else
    warn "Not logged in to GitHub; private skills will fail. Fix: gh auth login, then ./setup.sh"
  fi
fi
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git # lets git (and so pi) clone private repos with this login
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    MISE_GITHUB_TOKEN="$(gh auth token)"
    export MISE_GITHUB_TOKEN
  fi
fi

# 5. The other tools from mise.toml.
say "Installing tools"
mise install --yes

# Make new terminals find the tools:
# - `mise activate` in .zshrc / .bashrc, for terminals you type in
# - mise's shims at the top of .zshenv / .bashrc, for shells that run one
#   command, like herdr's over SSH. Ubuntu's .bashrc stops early for those,
#   so the line has to come first.
# shellcheck disable=SC2016
shims_line='export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH" # added by agent-kit setup.sh'
# shellcheck disable=SC2016
case "$(basename "${SHELL:-bash}")" in
  zsh) rc="$HOME/.zshrc" env_rc="$HOME/.zshenv" line='eval "$("$HOME/.local/bin/mise" activate zsh)"' ;;
  bash) rc="$HOME/.bashrc" env_rc="$HOME/.bashrc" line='eval "$("$HOME/.local/bin/mise" activate bash)"' ;;
  *) rc="" env_rc="" line="" ;;
esac
if [ -z "$rc" ]; then
  warn "Unknown shell $SHELL: add mise to it yourself (https://mise.jdx.dev/getting-started.html)"
else
  if ! grep -qF "$shims_line" "$env_rc" 2>/dev/null; then
    { printf '%s\n' "$shims_line"; cat "$env_rc" 2>/dev/null || true; } >"$env_rc.agent-kit.tmp"
    cat "$env_rc.agent-kit.tmp" >"$env_rc" # keeps the file's permissions and symlinks
    rm -f "$env_rc.agent-kit.tmp"
    say "Added mise's shims to the top of $env_rc"
  fi
  if ! grep -qF "$line" "$rc" 2>/dev/null; then
    printf '\n# added by agent-kit setup.sh\n%s\n' "$line" >>"$rc"
    say "Added mise to $rc"
  fi
fi

# 6. GitHub Copilot in pi, so pi works (and can fix a failed step) from here on.
if ! pi auth check --provider github-copilot >/dev/null 2>&1 && interactive; then
  say "Logging in to GitHub Copilot"
  echo "    pi opens next: type /login, choose GitHub Copilot (leave the Enterprise"
  echo "    domain blank unless you use *.ghe.com), then type /quit to continue."
  printf '    Press Enter to open pi. '
  read -r _
  (cd "$HOME" && pi --no-session) || true
fi

# 7. pi settings and skills, all declared in pi-settings.json and skills/:
#    - every key in pi-settings.json is set to the team value, and a key the
#      team has removed since the last run is removed; your other pi
#      settings are left alone
#    - its "packages" replace the ones an earlier run added (marked
#      "agentKit": true); packages you added yourself stay
#    - skills/ in this repo is added to pi's skill folders
say "Applying pi settings"
unpinned="$(jq -r '.packages // [] | .[] | if type == "string" then . else .source end
  | select(test("^[./~]") | not) | select(test("@(v?[0-9][^@/:]*|[0-9a-f]{40})$") | not)' pi-settings.json)"
if [ -n "$unpinned" ]; then
  die "pi-settings.json: pin each package to a version tag (@v1.2.0, @1.2.0) or a full commit SHA, so every machine gets the same version. Branches like @main move. Not pinned: $unpinned"
fi
settings="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"
applied="${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit/pi-settings-applied.json" # what the last run set
mkdir -p "$(dirname "$settings")" "$(dirname "$applied")"
if [ ! -f "$settings" ]; then echo '{}' >"$settings"; fi
if [ ! -f "$applied" ]; then echo '{}' >"$applied"; fi
jq --slurpfile team pi-settings.json --slurpfile last "$applied" --arg skills "$KIT_DIR/skills" '
  def leaves: [paths(type != "object") | select(all(.[]; type == "string"))];
  ($team[0] | del(.packages)) as $new
  | ($new | leaves) as $kept
  | ($team[0].packages // [] | map((if type == "string" then {source: .} else . end) + {agentKit: true})) as $packages
  | reduce (($last[0].settings // {}) | leaves[] | select(. as $p | $kept | any(. == $p) | not)) as $p
      (.; try delpaths([$p]) catch .)
  | . * $new
  | .packages = ([(.packages // [])[] | select(type == "object" and .agentKit == true | not)] + $packages)
  | .skills = ((.skills // []) - [$skills, $last[0].skills] + [$skills])' \
  "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"
jq --arg skills "$KIT_DIR/skills" '{settings: del(.packages), skills: $skills}' pi-settings.json >"$applied"

# 8. Download the skill packages now, so a bad link fails here, not in pi.
say "Installing skill packages"
GIT_TERMINAL_PROMPT=0 pi update --extensions </dev/null

# 9. herdr integration: herdr shows each pi pane's state and restores sessions.
say "Connecting herdr to pi"
herdr integration install pi

# Summary
rm -f .setup-failure.md
echo
say "Done: agent-kit $(git rev-parse --short HEAD 2>/dev/null || echo '(not a git checkout)')," \
  "herdr $(herdr --version | awk '{print $2}'), pi $(pi --version)," \
  "skill packages: $(jq '.packages // [] | length' pi-settings.json)," \
  "skills in skills/: $(find skills -name SKILL.md | wc -l | tr -d ' ')"
if pi auth check --provider github-copilot >/dev/null 2>&1; then
  echo "    GitHub Copilot: logged in."
else
  echo "    Next (once per machine): run pi, type /login, choose GitHub Copilot."
  echo "    Leave the Enterprise domain blank unless you use *.ghe.com."
fi
echo "    Open a new terminal to use the tools."

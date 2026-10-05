#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted strings are jq programs or are run later
# For maintainers: runs setup.sh on a pretend new machine (a throwaway HOME
# with a bare PATH) and checks the result. Your real setup isn't touched.
#
#   scripts/test.sh        (KEEP=1 keeps the sandbox for a look afterwards)
#
# Runs setup.sh: on a new machine (then checks that new terminals and
# one-command shells, like herdr's over SSH, find the tools); after the team
# adds skills and a setting, with a mise older than the kit needs; after the
# team removes them; with unpinned
# links (must be refused); with a broken link (must fail and point to pi);
# and after the team pushes a fix (setup.sh must pull it). A package and a
# setting the developer added themselves must survive all of it.
set -euo pipefail

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-test.XXXXXX")" && pwd)"
HOME_DIR="$SANDBOX/home"
KIT="$SANDBOX/kit"
mkdir -p "$HOME_DIR" "$KIT"
tar -C "$KIT_SRC" --exclude=.git --exclude=.setup-failure.md -cf - . | tar -C "$KIT" -xf -

GITHUB_PACKAGE='{"source": "git:github.com/anthropics/skills@8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4", "skills": ["skills/pdf"]}'
failed=0
pi_pid=""
trap 'if [ -n "$pi_pid" ]; then kill "$pi_pid" 2>/dev/null || true; fi' EXIT
ok() { printf '  PASS %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; failed=1; }

# A bare environment, like a new machine. Your GitHub token is passed in so
# private repos work as they would after `gh auth login`, and so are your
# proxy and certificate settings, so downloads work as they do for you.
token="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
ENV=(env -i HOME="$HOME_DIR" PATH="$HOME_DIR/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  SHELL=/bin/bash TERM="${TERM:-xterm}" LANG=C.UTF-8)
if [ -n "$token" ]; then ENV+=(GITHUB_TOKEN="$token"); fi
for var in HTTPS_PROXY HTTP_PROXY NO_PROXY ALL_PROXY https_proxy http_proxy no_proxy all_proxy \
  SSL_CERT_FILE NODE_EXTRA_CA_CERTS; do
  if [ -n "${!var:-}" ]; then ENV+=("$var=${!var}"); fi
done
WITH_TOOLS='eval "$(mise activate bash --shims)"; cd "$0"; exec "$@"'
in_sandbox() { "${ENV[@]}" bash -c "$WITH_TOOLS" "$@"; } # in_sandbox <dir> <command...>
sandbox_jq() { in_sandbox "$KIT" jq "$@"; }

# run_setup <n> <description> [expect-fail]
run_setup() {
  local log="$SANDBOX/setup$1.log"
  if "${ENV[@]}" bash "$KIT/setup.sh" </dev/null >"$log" 2>&1; then
    if [ -n "${3:-}" ]; then
      bad "setup.sh run $1 ($2) should have failed"
    elif grep -q 'Setup failed' "$log"; then
      bad "setup.sh run $1 ($2) succeeded but reported a failure; see $log"
    else
      ok "setup.sh run $1 ($2)"
    fi
  elif [ -n "${3:-}" ]; then
    ok "setup.sh run $1 ($2) failed as it should"
  else
    bad "setup.sh run $1 ($2); last lines of $log:"
    tail -15 "$log"
    exit 1
  fi
}

# Ask pi what it loaded: sets $loaded (skill names) and $model.
# The dummy token only makes pi treat Copilot as logged in; PI_OFFLINE and
# sending no prompt mean nothing leaves the machine.
ask_pi() {
  rm -f "$SANDBOX/rpc.in" "$SANDBOX/rpc.out"
  mkfifo "$SANDBOX/rpc.in"
  (exec "${ENV[@]}" PI_OFFLINE=1 COPILOT_GITHUB_TOKEN=dummy bash -c "$WITH_TOOLS" "$SANDBOX" \
    pi --mode rpc --no-session -na) <"$SANDBOX/rpc.in" >"$SANDBOX/rpc.out" 2>/dev/null &
  pi_pid=$!
  exec 3>"$SANDBOX/rpc.in"
  printf '%s\n' '{"type":"get_commands"}' '{"type":"get_state"}' >&3
  for _ in $(seq 60); do
    if [ "$(grep -c '"type":"response"' "$SANDBOX/rpc.out" || true)" -ge 2 ]; then break; fi
    sleep 0.5
  done
  exec 3>&-
  kill "$pi_pid" 2>/dev/null || true
  wait "$pi_pid" 2>/dev/null || true
  pi_pid=""
  loaded=" $(sandbox_jq -r 'select(.command == "get_commands") | .data.commands[]
    | select(.source == "skill") | .name | ltrimstr("skill:")' "$SANDBOX/rpc.out" | tr '\n' ' ')"
  model="$(sandbox_jq -r 'select(.command == "get_state") | .data
    | .model.provider + "/" + .model.id + " " + .thinkingLevel' "$SANDBOX/rpc.out")"
}
# expect_skills "<description>" name... [-- absent-name...]
expect_skills() {
  local what="$1" word missing="" present=""
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    case "$loaded" in *" $1 "*) ;; *) missing="$missing $1" ;; esac
    shift
  done
  if [ $# -gt 0 ]; then shift; fi
  for word in "$@"; do
    case "$loaded" in *" $word "*) present="$present $word" ;; esac
  done
  if [ -z "$missing$present" ]; then
    ok "$what (pi loads:$loaded)"
  else
    bad "$what: missing [${missing# }], unexpected [${present# }], pi loads:$loaded"
  fi
}
edit_team() { # edit_team <jq args...>: changes the kit's pi-settings.json
  sandbox_jq "$@" "$KIT/pi-settings.json" >"$SANDBOX/team.json"
  mv "$SANDBOX/team.json" "$KIT/pi-settings.json"
}
set_team_packages() { edit_team --argjson p "$1" '.packages = $p'; }

echo "Sandbox: $SANDBOX"
# Like Ubuntu's .bashrc, which stops early in shells that run one command.
printf '# not running interactively: stop here\ncase $- in *i*) ;; *) return ;; esac\n' \
  >"$HOME_DIR/.bashrc"
run_setup 1 "new machine"
min_mise="$(sed -n 's/^min_version *= *"\(.*\)"/\1/p' "$KIT/mise.toml")"
expect_mise() { # expect_mise <description>: mise is in the sandbox, at min_version or newer
  local version
  version="$("${ENV[@]}" "$HOME_DIR/.local/bin/mise" --version 2>/dev/null || true)"
  version="${version%% *}"
  if [ -n "$version" ] && [ "$(printf '%s\n' "$min_mise" "$version" | sort -V | sed -n 1p)" = "$min_mise" ]; then
    ok "$1 (mise $version, needs $min_mise)"
  else
    bad "$1: mise is '${version:-missing}', needs $min_mise or newer"
  fi
}
expect_mise "mise installed"
while read -r tool installed; do
  if [ "$installed" = true ]; then ok "$tool installed"; else bad "$tool not installed in the sandbox"; fi
done < <(in_sandbox "$KIT" mise ls --current --json | sandbox_jq -r --arg home "$HOME_DIR" \
  'to_entries[] | "\(.key) \(any(.value[]; .installed and (.install_path | startswith($home))))"')

# New terminals, with only the system PATH (as on a new Mac): one you type in,
# and one that runs one command, as herdr's SSH connection does.
STOCK=(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin:/usr/sbin:/sbin TERM="${TERM:-xterm}" LANG=C.UTF-8)
path="$(cd "$HOME_DIR" && "${STOCK[@]}" bash -ic 'echo "$MISE_SHELL $(command -v herdr)"' </dev/null 2>/dev/null || true)"
case "$path" in
  "bash $HOME_DIR"/.local/share/mise/*) ok "a new terminal activates mise and finds the tools" ;;
  *) bad "a new terminal: MISE_SHELL and herdr are '${path:-nothing}', expected bash and a path in the sandbox" ;;
esac
path="$(cd "$HOME_DIR" && "${STOCK[@]}" bash -c '. ~/.bashrc; command -v herdr' </dev/null 2>/dev/null || true)"
case "$path" in
  "$HOME_DIR"/.local/share/mise/shims/*) ok "a one-command shell (like over SSH) finds the tools" ;;
  *) bad "a one-command shell finds herdr at '${path:-nothing}'" ;;
esac

# The developer adds a package and a setting of their own; the team adds a
# GitHub package, a skill folder in skills/ and a setting.
mkdir -p "$SANDBOX/personal/skills/personal-skill"
printf -- '---\nname: personal-skill\ndescription: test skill. Never use it.\n---\nTest.\n' \
  >"$SANDBOX/personal/skills/personal-skill/SKILL.md"
settings="$HOME_DIR/.pi/agent/settings.json"
sandbox_jq --arg p "$SANDBOX/personal" '.packages += [$p] | .theme = "dark"' "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"
set_team_packages "[$GITHUB_PACKAGE]"
edit_team '.hideThinkingBlock = true'
mkdir -p "$KIT/skills/team-skill"
printf -- '---\nname: team-skill\ndescription: test skill. Never use it.\n---\nTest.\n' \
  >"$KIT/skills/team-skill/SKILL.md"
# Meanwhile this machine's mise is older than the kit needs.
"${ENV[@]}" bash -c 'curl -fsSL https://mise.run | MISE_VERSION=v2026.10.0 MISE_INSTALL_HELP=0 sh' >/dev/null 2>&1
run_setup 2 "team adds skills and a setting; mise is too old"
expect_mise "old mise updated"

if sandbox_jq -e --slurpfile team "$KIT/pi-settings.json" --arg skills "$KIT/skills" \
  '. as $s | ($team[0] | del(.packages) | to_entries | all(.value == $s[.key]))
   and (.skills | any(.[]; . == $skills))' "$settings" >/dev/null; then
  ok "pi settings have the team defaults and the skills/ folder"
else
  bad "pi settings wrong: $(cat "$settings")"
fi
ask_pi
expect_skills "GitHub package, skills/ folder and personal package all load" pdf team-skill personal-skill
if [ "$model" = "github-copilot/gpt-6-luna xhigh" ]; then
  ok "pi starts on $model"
else
  bad "pi starts on '${model:-nothing}', expected 'github-copilot/gpt-6-luna xhigh'"
fi

# The team removes both skills and the setting.
set_team_packages "[]"
edit_team 'del(.hideThinkingBlock)'
rm -rf "$KIT/skills/team-skill"
run_setup 3 "team removes skills and the setting"
ask_pi
expect_skills "team skills gone, personal package kept" personal-skill -- pdf team-skill
if sandbox_jq -e '(has("hideThinkingBlock") | not) and .theme == "dark"' "$settings" >/dev/null; then
  ok "team setting removed, personal setting kept"
else
  bad "settings after the team removed one: $(cat "$settings")"
fi
activate_lines="$(grep -c 'mise" activate bash' "$HOME_DIR/.bashrc" || true)"
shims_lines="$(grep -c 'mise/shims' "$HOME_DIR/.bashrc" || true)"
if [ "$activate_lines/$shims_lines" = 1/1 ] && head -1 "$HOME_DIR/.bashrc" | grep -q 'mise/shims'; then
  ok "shell setup added once across three runs, shims first"
else
  bad "shell setup lines: activate $activate_lines, shims $shims_lines; first line: $(head -1 "$HOME_DIR/.bashrc")"
fi

# Unpinned links, and links to a branch, are refused before anything is installed.
set_team_packages '["git:github.com/anthropics/skills", "git:github.com/anthropics/skills@main"]'
run_setup 4 "unpinned links" expect-fail
if grep -q 'pin each package' "$SANDBOX/setup4.log" && grep -q 'anthropics/skills@main' "$SANDBOX/setup4.log"; then
  ok "setup explains that links must be pinned, and refuses @main"
else
  bad "no pinning message for both links; see $SANDBOX/setup4.log"
fi

# A broken link: setup must stop, describe the failure, and point to pi.
set_team_packages '["git:github.com/agent-kit-test-no-such-org/no-such-repo@v0.0.0"]'
run_setup 5 "broken link" expect-fail
if grep -q 'Step: Installing skill packages' "$KIT/.setup-failure.md" 2>/dev/null &&
  grep -q 'pi -a @.setup-failure.md' "$SANDBOX/setup5.log"; then
  ok "failure note names the step, and setup points to pi"
else
  bad "no usable failure note or pi hint; see $SANDBOX/setup5.log"
fi

# The team pushes a fix. The developer's kit is now a clone, and setup.sh
# must pull the fix by itself.
G=(git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c init.defaultBranch=main)
"${G[@]}" -C "$KIT" init -q
"${G[@]}" -C "$KIT" add -A
"${G[@]}" -C "$KIT" commit -qm "the kit with the broken link"
git clone -q --bare "$KIT" "$SANDBOX/upstream.git"
git -C "$KIT" remote add origin "$SANDBOX/upstream.git"
git -C "$KIT" fetch -q origin
git -C "$KIT" branch -q -u origin/main
git clone -q "$SANDBOX/upstream.git" "$SANDBOX/teammate"
sandbox_jq '.packages = []' "$SANDBOX/teammate/pi-settings.json" >"$SANDBOX/team.json"
mv "$SANDBOX/team.json" "$SANDBOX/teammate/pi-settings.json"
"${G[@]}" -C "$SANDBOX/teammate" commit -qam "fix the link"
git -C "$SANDBOX/teammate" push -q origin main
run_setup 6 "team pushed a fix"
if [ "$(git -C "$KIT" rev-parse HEAD)" = "$(git -C "$SANDBOX/upstream.git" rev-parse main)" ]; then
  ok "setup pulled the team's fix"
else
  bad "setup didn't pull; see $SANDBOX/setup6.log"
fi
if [ ! -e "$KIT/.setup-failure.md" ]; then
  ok "failure note removed after a clean run"
else
  bad "failure note still there after a clean run"
fi

if [ "$failed" = 0 ] && [ -z "${KEEP:-}" ]; then
  rm -rf "$SANDBOX"
  echo "All passed."
else
  echo "Sandbox kept at $SANDBOX"
fi
exit "$failed"

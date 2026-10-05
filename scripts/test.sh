#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted strings are jq programs or are run later
# For maintainers: runs setup.sh on a pretend new machine (a throwaway HOME
# with a bare PATH) and checks the result. Your real setup isn't touched.
#
#   scripts/test.sh        (KEEP=1 keeps the sandbox for a look afterwards)
#
# Runs setup.sh: on a new machine; after the team adds skills (a GitHub
# package and a folder in skills/); after the team removes them; with an
# unpinned link (must be refused); with a broken link (must fail and point
# to pi); and after fixing it. A package the developer added themselves
# must survive all of it.
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
# private repos work as they would after `gh auth login`.
token="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
ENV=(env -i HOME="$HOME_DIR" PATH="$HOME_DIR/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  SHELL=/bin/bash TERM="${TERM:-xterm}" LANG=C.UTF-8)
if [ -n "$token" ]; then ENV+=(GITHUB_TOKEN="$token"); fi
WITH_TOOLS='eval "$(mise activate bash --shims)"; cd "$0"; exec "$@"'
in_sandbox() { "${ENV[@]}" bash -c "$WITH_TOOLS" "$@"; } # in_sandbox <dir> <command...>
sandbox_jq() { in_sandbox "$KIT" jq "$@"; }

# run_setup <n> <description> [expect-fail]
run_setup() {
  local log="$SANDBOX/setup$1.log"
  if "${ENV[@]}" bash "$KIT/setup.sh" </dev/null >"$log" 2>&1; then
    if [ -n "${3:-}" ]; then bad "setup.sh run $1 ($2) should have failed"; else ok "setup.sh run $1 ($2)"; fi
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
set_team_packages() {
  sandbox_jq --argjson p "$1" '.packages = $p' "$KIT/pi-settings.json" >"$SANDBOX/team.json"
  mv "$SANDBOX/team.json" "$KIT/pi-settings.json"
}

echo "Sandbox: $SANDBOX"
run_setup 1 "new machine"
for tool in mise herdr pi node gh rg fd jq; do
  path="$(in_sandbox "$KIT" bash -c "command -v $tool" || true)"
  case "$path" in
    "$HOME_DIR"/*) ok "$tool installed" ;;
    *) bad "$tool not installed in the sandbox (found: ${path:-nothing})" ;;
  esac
done

# The developer adds a package of their own; the team adds a GitHub package
# and a skill folder in skills/.
mkdir -p "$SANDBOX/personal/skills/personal-skill"
printf -- '---\nname: personal-skill\ndescription: test skill. Never use it.\n---\nTest.\n' \
  >"$SANDBOX/personal/skills/personal-skill/SKILL.md"
settings="$HOME_DIR/.pi/agent/settings.json"
sandbox_jq --arg p "$SANDBOX/personal" '.packages += [$p]' "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"
set_team_packages "[$GITHUB_PACKAGE]"
mkdir -p "$KIT/skills/team-skill"
printf -- '---\nname: team-skill\ndescription: test skill. Never use it.\n---\nTest.\n' \
  >"$KIT/skills/team-skill/SKILL.md"
run_setup 2 "team adds skills"

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

# The team removes both skills.
set_team_packages "[]"
rm -rf "$KIT/skills/team-skill"
run_setup 3 "team removes skills"
ask_pi
expect_skills "team skills gone, personal package kept" personal-skill -- pdf team-skill
if [ "$(grep -c 'mise activate bash' "$HOME_DIR/.bashrc")" = 1 ]; then
  ok "shell setup added once across three runs"
else
  bad "shell setup line added $(grep -c 'mise activate bash' "$HOME_DIR/.bashrc") times"
fi

# An unpinned link is refused before anything is installed.
set_team_packages '["git:github.com/anthropics/skills"]'
run_setup 4 "unpinned link" expect-fail
if grep -q 'pin each package' "$SANDBOX/setup4.log"; then
  ok "setup explains that links must be pinned"
else
  bad "no pinning message; see $SANDBOX/setup4.log"
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
set_team_packages "[]"
run_setup 6 "link fixed"
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

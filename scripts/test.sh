#!/usr/bin/env bash
# For maintainers: runs setup.sh on a pretend new machine (a throwaway HOME
# with a bare PATH) and checks the result. Your real setup isn't touched.
#
#   scripts/test.sh        (KEEP=1 keeps the sandbox for a look afterwards)
#
# It runs setup.sh on a new machine, after adding two skills (one from
# GitHub, one from skills/), after removing one, with a broken link (it
# must fail and point to pi), and after fixing the link.
set -euo pipefail

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-test.XXXXXX")" && pwd)"
HOME_DIR="$SANDBOX/home"
KIT="$SANDBOX/kit"
mkdir -p "$HOME_DIR" "$KIT"
tar -C "$KIT_SRC" --exclude=.git --exclude=.agents --exclude=apm_modules -cf - . | tar -C "$KIT" -xf -

GITHUB_SKILL="anthropics/skills/skills/pdf#8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4"
failed=0
ok() { printf '  PASS %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; failed=1; }

# A bare environment, like a new machine. Your GitHub token is passed in so
# private repos work as they would after `gh auth login`.
token="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
ENV=(env -i HOME="$HOME_DIR" PATH="$HOME_DIR/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  SHELL=/bin/bash TERM="${TERM:-xterm}" LANG=C.UTF-8)
if [ -n "$token" ]; then ENV+=(GITHUB_TOKEN="$token"); fi
# shellcheck disable=SC2016
WITH_TOOLS='eval "$(mise activate bash --shims)"; cd "$0"; exec "$@"'
in_sandbox() { "${ENV[@]}" bash -c "$WITH_TOOLS" "$@"; } # in_sandbox <dir> <command...>

run_setup() {
  if "${ENV[@]}" bash "$KIT/setup.sh" </dev/null >"$SANDBOX/setup$1.log" 2>&1; then
    ok "setup.sh run $1 ($2)"
  else
    bad "setup.sh run $1 ($2); last lines of $SANDBOX/setup$1.log:"
    tail -15 "$SANDBOX/setup$1.log"
    exit 1
  fi
}
# shellcheck disable=SC2012 # skill folder names are plain
installed_skills() { ls "$KIT/.agents/skills" 2>/dev/null | tr '\n' ' '; }
# has_all "<space-separated list>" word...: true if every word is in the list.
has_all() {
  local list=" $1 " word
  shift
  for word in "$@"; do
    case "$list" in *" $word "*) ;; *) return 1 ;; esac
  done
}

echo "Sandbox: $SANDBOX"
run_setup 1 "new machine"

for tool in mise herdr pi apm node gh rg fd jq; do
  path="$(in_sandbox "$KIT" bash -c "command -v $tool" || true)"
  case "$path" in
    "$HOME_DIR"/*) ok "$tool installed" ;;
    *) bad "$tool not installed in the sandbox (found: ${path:-nothing})" ;;
  esac
done

# Add a skill from GitHub by hand, and a skill written in this repo with apm.
printf '    - %s\n' "$GITHUB_SKILL" >>"$KIT/apm.yml"
mkdir -p "$KIT/skills/sandbox-test"
printf -- '---\nname: sandbox-test\ndescription: agent-kit test skill. Never use it.\n---\nTest.\n' \
  >"$KIT/skills/sandbox-test/SKILL.md"
in_sandbox "$KIT" apm install ./skills/sandbox-test >"$SANDBOX/apm-add.log" 2>&1
run_setup 2 "two skills added"

if has_all "$(installed_skills)" pdf sandbox-test; then
  ok "both skills installed: $(installed_skills)"
else
  bad "expected pdf and sandbox-test, found: $(installed_skills)"
fi

settings="$HOME_DIR/.pi/agent/settings.json"
# shellcheck disable=SC2016 # jq program, not shell
if in_sandbox "$KIT" jq -e --slurpfile team "$KIT/pi-settings.json" --arg skills "$KIT/.agents/skills" \
  '. as $s | ($team[0] | to_entries | all(.value == $s[.key])) and (.skills | any(.[]; . == $skills))' \
  "$settings" >/dev/null; then
  ok "pi settings have the team defaults and the skills folder"
else
  bad "pi settings wrong: $(cat "$settings")"
fi

# Ask pi itself what it loaded. The dummy token only makes pi treat Copilot as
# logged in; PI_OFFLINE and sending no prompt mean nothing leaves the machine.
mkfifo "$SANDBOX/rpc.in"
(exec "${ENV[@]}" PI_OFFLINE=1 COPILOT_GITHUB_TOKEN=dummy bash -c "$WITH_TOOLS" "$SANDBOX" \
  pi --mode rpc --no-session -na) <"$SANDBOX/rpc.in" >"$SANDBOX/rpc.out" 2>/dev/null &
pi_pid=$!
trap 'kill "$pi_pid" 2>/dev/null || true' EXIT
exec 3>"$SANDBOX/rpc.in"
printf '%s\n' '{"type":"get_commands"}' '{"type":"get_state"}' >&3
for _ in $(seq 60); do
  if [ "$(grep -c '"type":"response"' "$SANDBOX/rpc.out" || true)" -ge 2 ]; then break; fi
  sleep 0.5
done
exec 3>&-
kill "$pi_pid" 2>/dev/null || true

pi_skills="$(in_sandbox "$KIT" jq -r 'select(.command == "get_commands") | .data.commands[]
  | select(.source == "skill") | .name' "$SANDBOX/rpc.out" | tr '\n' ' ')"
if has_all "$pi_skills" skill:pdf skill:sandbox-test; then
  ok "pi loads both skills"
else
  bad "pi loaded: ${pi_skills:-no skills}"
fi
pi_model="$(in_sandbox "$KIT" jq -r 'select(.command == "get_state") | .data
  | .model.provider + "/" + .model.id + " " + .thinkingLevel' "$SANDBOX/rpc.out")"
if [ "$pi_model" = "github-copilot/gpt-6-luna xhigh" ]; then
  ok "pi starts on $pi_model"
else
  bad "pi starts on '${pi_model:-nothing}', expected 'github-copilot/gpt-6-luna xhigh'"
fi

# Remove the GitHub skill by deleting its line.
grep -vF "$GITHUB_SKILL" "$KIT/apm.yml" >"$KIT/apm.yml.tmp"
mv "$KIT/apm.yml.tmp" "$KIT/apm.yml"
run_setup 3 "one skill removed"
if [ "$(installed_skills)" = "sandbox-test " ]; then
  ok "deleted line removed its skill"
else
  bad "after removing pdf, found: $(installed_skills)"
fi
if [ "$(grep -c 'mise activate bash' "$HOME_DIR/.bashrc")" = 1 ]; then
  ok "shell setup added once across three runs"
else
  bad "shell setup line added $(grep -c 'mise activate bash' "$HOME_DIR/.bashrc") times"
fi

# A broken skill link: setup must stop, describe the failure, and point to pi.
BROKEN="agent-kit-test-no-such-org/no-such-repo/skill#v0.0.0"
cp "$KIT/apm.yml" "$SANDBOX/apm.yml.good"
printf '    - %s\n' "$BROKEN" >>"$KIT/apm.yml"
if "${ENV[@]}" bash "$KIT/setup.sh" </dev/null >"$SANDBOX/setup4.log" 2>&1; then
  bad "setup.sh run 4 (broken skill link) should have failed"
else
  ok "setup.sh run 4 (broken skill link) failed as it should"
fi
if grep -q 'Step: Installing skills' "$KIT/.setup-failure.md" 2>/dev/null &&
  grep -q 'pi -a @.setup-failure.md' "$SANDBOX/setup4.log"; then
  ok "failure note names the step, and setup points to pi"
else
  bad "no usable failure note or pi hint; see $SANDBOX/setup4.log"
fi
cp "$SANDBOX/apm.yml.good" "$KIT/apm.yml"
run_setup 5 "link fixed"
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

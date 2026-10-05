#!/usr/bin/env bash
# Fresh-machine test. Runs bootstrap.sh twice in a throwaway HOME with a bare
# PATH, then runs doctor.sh and a few test-only checks. Your real home
# directory is never touched. CI runs this on macOS and Linux.
#
# Usage: scripts/test-sandbox.sh
#   KEEP=1      keep the sandbox afterwards for inspection
#   NO_TOKEN=1  don't pass your GitHub token in (tests the anonymous path)
#
# Your GitHub token ($GITHUB_TOKEN or `gh auth token`) is passed in so private
# repos in config/pi-packages.txt can be cloned, as on a logged-in machine.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$KIT_DIR/lib/common.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-test.XXXXXX")"
SBX_HOME="$SANDBOX/home"
SBX_KIT="$SANDBOX/kit"
WORK="$SANDBOX/work"
mkdir -p "$SBX_HOME" "$SBX_KIT" "$WORK"

TOKEN=""
if [ -z "${NO_TOKEN:-}" ]; then
  TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
fi

# A bare environment, like a new laptop: no Homebrew, nvm or host mise.
SBX_ENV=(env -i HOME="$SBX_HOME" PATH="$SBX_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  SHELL=/bin/bash TERM="${TERM:-xterm}" LANG=C.UTF-8)
if [ -n "$TOKEN" ]; then SBX_ENV+=(GITHUB_TOKEN="$TOKEN"); fi
# Runs "$@" from directory $0 with the sandbox's tools on PATH.
# shellcheck disable=SC2016
SBX_SHELL='eval "$(mise activate bash --shims)"; cd "$0"; exec "$@"'

run() { "${SBX_ENV[@]}" "$@"; }
in_sbx() { run bash -c "$SBX_SHELL" "$@"; }
# Make a one-skill pi package at $SANDBOX/<name>.
make_package() {
  mkdir -p "$SANDBOX/$1/skills/$1"
  printf '{ "name": "%s", "version": "0.0.0", "keywords": ["pi-package"] }\n' "$1" \
    >"$SANDBOX/$1/package.json"
  printf -- '---\nname: %s\ndescription: agent-kit sandbox test skill. Never use it.\n---\nTest.\n' "$1" \
    >"$SANDBOX/$1/skills/$1/SKILL.md"
}
bootstrap_pass() {
  local n="$1" log="$SANDBOX/bootstrap$1.log"
  if run bash "$SBX_KIT/bootstrap.sh" </dev/null >"$log" 2>&1; then
    pass "bootstrap run $n exited 0"
  else
    fail "bootstrap run $n failed; last lines of $log:"
    tail -20 "$log"
    echo "Sandbox kept at $SANDBOX"
    exit 1
  fi
}

echo "Sandbox: $SANDBOX"
tar -C "$KIT_DIR" --exclude=.git -cf - . | tar -C "$SBX_KIT" -xf -
make_package agent-kit-smoke
make_package agent-kit-retired
PACKAGES="$SBX_KIT/config/pi-packages.txt"
TEAM_SETTINGS="$SBX_KIT/config/pi-settings.json"
cp "$PACKAGES" "$SANDBOX/pi-packages.orig"
cp "$TEAM_SETTINGS" "$SANDBOX/pi-settings.orig"
USER_SETTINGS="$SBX_HOME/.pi/agent/settings.json"
sbx_jq() { in_sbx "$WORK" jq "$@"; }

section "Bootstrap"
# Run 1: a new machine, with the real config plus two test packages.
printf '%s\n' "$SANDBOX/agent-kit-smoke" "$SANDBOX/agent-kit-retired" >>"$PACKAGES"
bootstrap_pass 1
# Run 2: the team adds three settings.
sbx_jq '. + {collapseChangelog: false, enableInstallTelemetry: true, hideThinkingBlock: false}' \
  "$SANDBOX/pi-settings.orig" >"$TEAM_SETTINGS"
bootstrap_pass 2
# Run 3: the developer changes one team setting themselves; the team changes
# another, drops a third, and retires a package.
sbx_jq '.enableInstallTelemetry = false' "$USER_SETTINGS" >"$USER_SETTINGS.tmp"
mv "$USER_SETTINGS.tmp" "$USER_SETTINGS"
sbx_jq '. + {collapseChangelog: true, enableInstallTelemetry: true}' \
  "$SANDBOX/pi-settings.orig" >"$TEAM_SETTINGS"
cp "$SANDBOX/pi-packages.orig" "$PACKAGES"
printf '%s\n' "$SANDBOX/agent-kit-smoke" >>"$PACKAGES"
bootstrap_pass 3

section "Doctor (inside the sandbox)"
# The dummy token only makes pi treat Copilot as logged in; PI_OFFLINE and
# sending no prompt mean nothing leaves the machine.
if in_sbx "$WORK" env PI_OFFLINE=1 COPILOT_GITHUB_TOKEN=dummy bash "$SBX_KIT/scripts/doctor.sh" \
  >"$SANDBOX/doctor.log" 2>&1; then
  pass "doctor reports no failures"
else
  fail "doctor reported failures:"
fi
sed 's/^/    /' "$SANDBOX/doctor.log"

section "Test-only checks"
rc_lines="$(grep -c 'mise activate bash' "$SBX_HOME/.bashrc" || true)"
if [ "$rc_lines" = 1 ]; then pass "shell activation added exactly once"; else fail "shell activation lines: $rc_lines"; fi

check_setting() {
  local key="$1" want="$2" why="$3" got
  got="$(sbx_jq -c ".$key" "$USER_SETTINGS")"
  if [ "$got" = "$want" ]; then pass "$why ($key = $got)"; else fail "$why: $key is $got, expected $want"; fi
}
check_setting collapseChangelog true "team setting change reached the machine"
check_setting enableInstallTelemetry false "developer's own setting was kept"
check_setting hideThinkingBlock null "setting dropped by the team was removed"

pi_list="$(in_sbx "$WORK" pi list 2>&1 || true)"
if printf '%s\n' "$pi_list" | grep -q 'agent-kit-retired'; then
  fail "package deleted from config/pi-packages.txt was not removed"
else
  pass "package deleted from config/pi-packages.txt was removed"
fi

# Ask pi over RPC what it actually loaded.
RPC_OUT="$SANDBOX/rpc.jsonl"
mkfifo "$SANDBOX/rpc.in"
# Each layer execs the next, so $! is pi itself and `kill` stops it.
(exec "${SBX_ENV[@]}" bash -c "$SBX_SHELL" "$WORK" \
  env PI_OFFLINE=1 COPILOT_GITHUB_TOKEN=dummy pi --mode rpc --no-session -na) \
  <"$SANDBOX/rpc.in" >"$RPC_OUT" 2>"$SANDBOX/rpc.err" &
PI_PID=$!
trap 'kill "$PI_PID" 2>/dev/null || true' EXIT
exec 3>"$SANDBOX/rpc.in"
printf '%s\n' '{"type":"get_commands"}' '{"type":"get_state"}' >&3
for _ in $(seq 60); do
  [ "$(grep -c '"type":"response"' "$RPC_OUT" 2>/dev/null || true)" -ge 2 ] && break
  sleep 0.5
done
exec 3>&-
sleep 1
kill "$PI_PID" 2>/dev/null || true
wait "$PI_PID" 2>/dev/null || true

skills="$(sbx_jq -r 'select(.command == "get_commands") | .data.commands[]
  | select(.source == "skill") | .name' "$RPC_OUT" 2>/dev/null || true)"
if printf '%s\n' "$skills" | grep -qx 'skill:agent-kit-smoke'; then
  pass "pi loads skills from packages ($(printf '%s\n' "$skills" | grep -c .) loaded):"
  printf '%s\n' "$skills" | sed 's/^/         /'
else
  fail "test skill not loaded (see $RPC_OUT and $SANDBOX/rpc.err)"
fi

want="$(sbx_jq -r '.defaultProvider + "/" + .defaultModel + " "
  + (.modelThinkingLevels[.defaultProvider + "/" + .defaultModel] // "medium")' "$SBX_KIT/config/pi-settings.json")"
got="$(sbx_jq -r 'select(.command == "get_state") | .data
  | .model.provider + "/" + .model.id + " " + .thinkingLevel' "$RPC_OUT" 2>/dev/null || true)"
if [ "$want" = "$got" ]; then pass "pi starts on $got"; else fail "pi starts on '${got:-nothing}', expected '$want'"; fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" = 0 ] && [ -z "${KEEP:-}" ]; then
  rm -rf "$SANDBOX"
else
  echo "Sandbox kept at $SANDBOX"
fi
[ "$FAILED" = 0 ]

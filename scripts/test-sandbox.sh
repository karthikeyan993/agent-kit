#!/usr/bin/env bash
# Fresh-machine test: runs bootstrap.sh twice in a throwaway HOME with a bare
# PATH, then checks the result. Your real home directory is never touched.
#
#   scripts/test-sandbox.sh            # deletes the sandbox if all checks pass
#   KEEP=1 scripts/test-sandbox.sh     # keep the sandbox to poke around
#   NO_TOKEN=1 scripts/test-sandbox.sh # don't pass your GitHub token in
#
# Your GitHub token (from $GITHUB_TOKEN or `gh auth token`) is passed in so
# private repos in pi-packages.txt can be cloned, like on a logged-in machine.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-test.XXXXXX")"
SBX_HOME="$SANDBOX/home"
SBX_KIT="$SANDBOX/kit"
WORK="$SANDBOX/work"
mkdir -p "$SBX_HOME" "$SBX_KIT" "$WORK"
FAILED=0

pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

TOKEN=""
if [ -z "${NO_TOKEN:-}" ]; then
  TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
fi

# Bare environment, like a new laptop: no Homebrew, nvm, or host mise on PATH.
run() {
  env -i HOME="$SBX_HOME" PATH="$SBX_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    SHELL=/bin/bash TERM="${TERM:-xterm}" LANG=C.UTF-8 \
    ${TOKEN:+GITHUB_TOKEN="$TOKEN"} "$@"
}
# Run a command in $1 with the sandbox's mise tools on PATH.
in_sbx() {
  run bash -c 'eval "$(mise activate bash --shims)"; cd "$0"; exec "$@"' "$@"
}

# Copy the kit and add a smoke-test skill package to prove skills load.
tar -C "$KIT_DIR" --exclude=.git -cf - . | tar -C "$SBX_KIT" -xf -
mkdir -p "$SANDBOX/smoke-pkg/skills/agent-kit-smoke"
echo '{ "name": "agent-kit-smoke", "version": "0.0.0", "keywords": ["pi-package"] }' \
  >"$SANDBOX/smoke-pkg/package.json"
cat >"$SANDBOX/smoke-pkg/skills/agent-kit-smoke/SKILL.md" <<'EOF'
---
name: agent-kit-smoke
description: Smoke-test skill for agent-kit's sandbox test. Never use it.
---
Smoke test.
EOF
printf '\n%s\n' "$SANDBOX/smoke-pkg" >>"$SBX_KIT/pi-packages.txt"

echo "Sandbox: $SANDBOX"
for n in 1 2; do
  echo "Running bootstrap.sh (pass $n, log: $SANDBOX/bootstrap$n.log)"
  if run bash "$SBX_KIT/bootstrap.sh" </dev/null >"$SANDBOX/bootstrap$n.log" 2>&1; then
    pass "bootstrap pass $n exited 0"
  else
    fail "bootstrap pass $n failed; tail of log:"
    tail -20 "$SANDBOX/bootstrap$n.log"
    echo "Sandbox kept at $SANDBOX"
    exit 1
  fi
done

# Tools resolve from the sandbox, not the host.
for tool in mise herdr pi node gh rg fd jq; do
  path="$(in_sbx "$WORK" bash -c "command -v $tool" 2>/dev/null || true)"
  case "$path" in
    "$SBX_HOME"/*) pass "$tool -> $(in_sbx "$WORK" "$tool" --version 2>&1 | head -1)" ;;
    *) fail "$tool not installed in sandbox (got: ${path:-nothing})" ;;
  esac
done

# Team pi defaults landed, and re-running didn't duplicate anything.
SETTINGS="$SBX_HOME/.pi/agent/settings.json"
JQ="$SBX_HOME/.local/share/mise/shims/jq"
if in_sbx "$WORK" jq -e --slurpfile team "$SBX_KIT/pi-settings.json" \
  '. as $s | $team[0] | to_entries | all(.value == $s[.key])' "$SETTINGS" >/dev/null; then
  pass "pi settings contain every key from pi-settings.json"
else
  fail "pi settings missing team defaults: $(cat "$SETTINGS")"
fi
want_pkgs="$(sed 's/#.*//' "$SBX_KIT/pi-packages.txt" | tr -d '[:blank:]' | grep -c . || true)"
have_pkgs="$(in_sbx "$WORK" jq '.packages | length' "$SETTINGS")"
[ "$want_pkgs" = "$have_pkgs" ] && pass "pi packages: $have_pkgs listed, $have_pkgs installed" ||
  fail "pi packages: expected $want_pkgs, settings has $have_pkgs"
rc_lines="$(grep -c 'mise activate bash' "$SBX_HOME/.bashrc" || true)"
[ "$rc_lines" = 1 ] && pass "shell activation added once" || fail "shell activation lines: $rc_lines"

# Ask pi over RPC what it loaded. The dummy token only marks Copilot as
# configured; PI_OFFLINE and sending no prompt mean nothing leaves the box.
RPC_OUT="$SANDBOX/rpc.jsonl"
mkfifo "$SANDBOX/rpc.in"
in_sbx "$WORK" env PI_OFFLINE=1 COPILOT_GITHUB_TOKEN=dummy pi --mode rpc --no-session -na \
  <"$SANDBOX/rpc.in" >"$RPC_OUT" 2>"$SANDBOX/rpc.err" &
PI_PID=$!
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

skills="$("$JQ" -r 'select(.command=="get_commands") | .data.commands[]
  | select(.source=="skill") | .name' "$RPC_OUT" 2>/dev/null || true)"
if printf '%s\n' "$skills" | grep -qx 'skill:agent-kit-smoke'; then
  pass "pi loads skills from packages ($(printf '%s\n' "$skills" | grep -c .) total):"
  printf '%s\n' "$skills" | sed 's/^/       /'
else
  fail "smoke skill not loaded; rpc output in $RPC_OUT, stderr in $SANDBOX/rpc.err"
fi

want="$("$JQ" -r '.defaultProvider + "/" + .defaultModel + " " +
  (.modelThinkingLevels[.defaultProvider + "/" + .defaultModel] // "medium")' "$SBX_KIT/pi-settings.json")"
got="$("$JQ" -r 'select(.command=="get_state") | .data
  | .model.provider + "/" + .model.id + " " + .thinkingLevel' "$RPC_OUT" 2>/dev/null || true)"
[ "$want" = "$got" ] && pass "pi starts on $got" || fail "pi starts on '${got:-nothing}', expected '$want'"

integrations="$(in_sbx "$WORK" herdr integration status 2>&1 || true)"
if printf '%s\n' "$integrations" | grep -q '^pi: current'; then
  pass "herdr pi integration installed"
else
  fail "herdr pi integration not current"
fi

if [ "$FAILED" = 0 ] && [ -z "${KEEP:-}" ]; then
  rm -rf "$SANDBOX"
  echo "All checks passed; sandbox removed."
else
  echo "Sandbox kept at $SANDBOX"
fi
exit "$FAILED"

# shellcheck shell=bash
# Shared helpers for bootstrap.sh, steps/ and scripts/. Source this file;
# don't run it. Callers set KIT_DIR to the repo root before sourcing.

# Paths used by the files that source this one.
# shellcheck disable=SC2034
{
  CONFIG_DIR="$KIT_DIR/config"
  PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  KIT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit"
}

if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_OFF=$'\033[0m'
else
  C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_OFF=''
fi

say() { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
warn() { printf '%s!! %s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die() {
  printf '%sxx %s %s\n' "$C_RED" "$C_OFF" "$*" >&2
  exit 1
}

# Check results, used by scripts/doctor.sh and scripts/test-sandbox.sh.
PASSED=0 WARNED=0 FAILED=0
pass() { PASSED=$((PASSED + 1)); printf '  %sPASS%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
caution() { WARNED=$((WARNED + 1)); printf '  %sWARN%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
fail() { FAILED=$((FAILED + 1)); printf '  %sFAIL%s %s\n' "$C_RED" "$C_OFF" "$*"; }
section() { printf '\n%s\n' "$*"; }

# Print each package source in config/pi-packages.txt, without comments.
team_packages() {
  sed 's/#.*//' "$CONFIG_DIR/pi-packages.txt" | tr -d ' \t\r' | grep . || true
}

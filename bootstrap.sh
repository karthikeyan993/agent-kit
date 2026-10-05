#!/usr/bin/env bash
# Sets up herdr, pi and the team skills on a Mac or a Linux VM.
#
# Usage: ./bootstrap.sh
#
# Runs every script in steps/ in order, then scripts/doctor.sh to show what,
# if anything, is left to do. Safe to re-run; run it again after `git pull`.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$KIT_DIR/lib/common.sh"

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "Unknown option: $1 (see ./bootstrap.sh --help)" ;;
esac

for step in "$KIT_DIR"/steps/*.sh; do
  # shellcheck source=/dev/null
  source "$step"
done

say "Setup finished. Health check:"
"$KIT_DIR/scripts/doctor.sh" || true
printf '\nOpen a new terminal so your shell picks up the tools.\n'

#!/usr/bin/env bash
# Static checks for every shell script and config file. CI runs this.
#
# Usage: scripts/lint.sh
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR"

scripts=(bootstrap.sh lib/*.sh steps/*.sh scripts/*.sh)

for f in "${scripts[@]}"; do
  bash -n "$f"
done
echo "bash syntax: ok"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${scripts[@]}"
else
  mise exec shellcheck@0.11.0 -- shellcheck -x "${scripts[@]}"
fi
echo "shellcheck: ok"

jq empty config/pi-settings.json
echo "config/pi-settings.json: valid JSON"

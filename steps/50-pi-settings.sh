# shellcheck shell=bash
# Step 5: apply the team pi defaults from config/pi-settings.json.
#
# For each team setting, a developer's machine gets the team value unless the
# developer changed it themselves; their own choices are kept. To tell the two
# apart, the state dir keeps a copy of what this step applied last time.
# The rules live in lib/settings.jq.

PI_SETTINGS="$PI_AGENT_DIR/settings.json"
APPLIED_SETTINGS="$KIT_STATE_DIR/pi-settings.applied.json"
mkdir -p "$PI_AGENT_DIR" "$KIT_STATE_DIR"
if [ ! -f "$PI_SETTINGS" ]; then echo '{}' >"$PI_SETTINGS"; fi
if [ ! -f "$APPLIED_SETTINGS" ]; then echo '{}' >"$APPLIED_SETTINGS"; fi

say "Applying team pi defaults"
jq -L "$KIT_DIR/lib" \
  --slurpfile team "$CONFIG_DIR/pi-settings.json" \
  --slurpfile prev "$APPLIED_SETTINGS" \
  'include "settings"; merge($team[0]; $prev[0])' \
  "$PI_SETTINGS" >"$PI_SETTINGS.tmp"
mv "$PI_SETTINGS.tmp" "$PI_SETTINGS"
cp "$CONFIG_DIR/pi-settings.json" "$APPLIED_SETTINGS"

# shellcheck shell=bash
# Step 6: make the installed team pi packages match config/pi-packages.txt.
# A state file records what the last run installed, so packages deleted from
# the list (or re-pinned to a new tag) are removed. Packages a developer
# installed themselves are never in the state file, so they're never touched.

APPLIED="$KIT_STATE_DIR/pi-packages.applied"
mkdir -p "$KIT_STATE_DIR"
CURRENT="$(team_packages)"

if [ -f "$APPLIED" ]; then
  while IFS= read -r old; do
    if [ -n "$old" ] && ! printf '%s\n' "$CURRENT" | grep -qxF "$old"; then
      say "pi remove $old (no longer in config/pi-packages.txt)"
      pi remove "$old" </dev/null || warn "Could not remove $old; remove it with: pi remove $old"
    fi
  done <"$APPLIED"
fi

while IFS= read -r src; do
  if [ -n "$src" ]; then
    say "pi install $src"
    pi install "$src" </dev/null
  fi
done <<<"$CURRENT"

printf '%s\n' "$CURRENT" >"$APPLIED"

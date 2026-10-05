# shellcheck shell=bash
# Step 7: connect herdr to the agents, so herdr shows each pane's agent
# state and can restore sessions. Re-installing keeps the hook files in step
# with the pinned herdr version.

say "Installing herdr integrations"
herdr integration install pi
if command -v claude >/dev/null 2>&1; then
  herdr integration install claude
fi

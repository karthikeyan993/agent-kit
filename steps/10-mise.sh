# shellcheck shell=bash
# Step 1: install mise, the tool manager that installs everything else.

export PATH="$HOME/.local/bin:$PATH" # where the mise installer puts mise

if ! command -v mise >/dev/null 2>&1; then
  say "Installing mise"
  curl -fsSL https://mise.run | sh
fi

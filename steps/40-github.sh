# shellcheck shell=bash
# Step 4: log in to GitHub so git (and `pi install git:...`) can read
# private skill repos. Skipped without a terminal, e.g. in tests and CI.

if ! gh auth status >/dev/null 2>&1 && [ -t 0 ]; then
  say "Logging in to GitHub"
  gh auth login --hostname github.com --git-protocol https --web
fi

if gh auth status >/dev/null 2>&1; then
  gh auth setup-git
else
  warn "GitHub login skipped; private skill repos will fail to install. Fix: gh auth login, then re-run."
fi

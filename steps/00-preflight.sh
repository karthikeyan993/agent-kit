# shellcheck shell=bash
# Step 0: stop early on an unsupported machine or missing system tools.

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64 | Darwin/x86_64 | Linux/x86_64 | Linux/aarch64) ;;
  *) die "Unsupported platform $(uname -s)/$(uname -m). Supported: macOS or Linux on x86_64 or arm64." ;;
esac

for cmd in curl git tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Missing '$cmd'. macOS: xcode-select --install. Debian/Ubuntu: sudo apt-get install -y $cmd"
  fi
done

if [ "$(id -u)" = 0 ]; then
  warn "Running as root: tools and logins will belong to root. On a VM, run as your own user."
fi

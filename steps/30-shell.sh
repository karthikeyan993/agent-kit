# shellcheck shell=bash
# Step 3: activate mise in new interactive shells so the tools are on PATH.

add_line_once() {
  local file="$1" line="$2"
  if [ -f "$file" ] && grep -qF "$line" "$file"; then
    return 0
  fi
  printf '\n# added by agent-kit (bootstrap.sh)\n%s\n' "$line" >>"$file"
  say "Added mise activation to $file"
}

# The single quotes are deliberate: the line is written to the rc file as-is.
# shellcheck disable=SC2016
case "$(basename "${SHELL:-bash}")" in
  zsh) add_line_once "$HOME/.zshrc" 'eval "$(mise activate zsh)"' ;;
  bash) add_line_once "$HOME/.bashrc" 'eval "$(mise activate bash)"' ;;
  *) warn "Unknown shell '$SHELL': add mise activation yourself (https://mise.jdx.dev/getting-started.html)" ;;
esac

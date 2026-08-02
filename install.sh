#!/bin/sh
# termi installer. POSIX sh on purpose: this script is what CHECKS for zsh,
# so it must run on machines that do not have zsh.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/termi"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/termi"
MARK_START="# >>> termi >>>"
MARK_END="# <<< termi <<<"

usage() {
  cat <<'EOF'
Usage: install.sh [--quotes FILE | --uninstall]
  (no args)       install termi: script, starter quotes, config, shell hooks
  --quotes FILE   merge quotes from FILE (one per line) into the installed set
  --uninstall     remove the script and shell hooks (keeps quotes and config)
EOF
}

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

require_zsh() {
  command -v zsh >/dev/null 2>&1 ||
    die "termi requires zsh (macOS: preinstalled; Debian/Ubuntu: sudo apt install zsh; Fedora: sudo dnf install zsh)"
}

zsh_snippet() {
  cat <<EOF
$MARK_START
[[ -o interactive && -x "\$HOME/.local/bin/termi" ]] && "\$HOME/.local/bin/termi"
$MARK_END
EOF
}

# TERMI_RAN (deliberately not exported) stops a double quote when
# .bash_profile sources .bashrc; nested shells still print.
bash_snippet() {
  cat <<EOF
$MARK_START
case \$- in *i*) [ -z "\${TERMI_RAN:-}" ] && [ -x "\$HOME/.local/bin/termi" ] && { TERMI_RAN=1; "\$HOME/.local/bin/termi"; } ;; esac
$MARK_END
EOF
}

append_block() {  # rcfile snippet_fn — no-op if the block is already there
  rc="$1"
  snip="$2"
  if [ ! -f "$rc" ]; then
    : > "$rc"
  fi
  if ! grep -qF "$MARK_START" "$rc"; then
    { printf '\n'; "$snip"; } >> "$rc"
  fi
}

remove_block() {  # rcfile — strip the marker block; cat-over preserves symlinks
  rc="$1"
  if [ ! -f "$rc" ]; then
    return 0
  fi
  if ! grep -qF "$MARK_START" "$rc"; then
    return 0
  fi
  tmp=$(mktemp)
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { inblock = 1; next }
    $0 == e { inblock = 0; next }
    !inblock' "$rc" > "$tmp"
  cat "$tmp" > "$rc"
  rm -f "$tmp"
}

merge_quotes() {  # file — append new unique non-empty lines, keep order
  src="$1"
  if [ ! -f "$src" ]; then
    die "quotes file not found: $src"
  fi
  mkdir -p "$DATA_DIR"
  if [ ! -f "$DATA_DIR/quotes.txt" ]; then
    : > "$DATA_DIR/quotes.txt"
  fi
  tmp=$(mktemp)
  awk 'NF && !seen[$0]++' "$DATA_DIR/quotes.txt" "$src" > "$tmp"
  cat "$tmp" > "$DATA_DIR/quotes.txt"
  rm -f "$tmp"
  printf 'Merged quotes from %s (%s total)\n' "$src" "$(wc -l < "$DATA_DIR/quotes.txt" | tr -d ' ')"
}

install_files() {
  require_zsh
  mkdir -p "$BIN_DIR" "$DATA_DIR" "$CONF_DIR"
  cp "$SELF_DIR/bin/termi" "$BIN_DIR/termi"
  chmod 755 "$BIN_DIR/termi"
  if [ ! -f "$DATA_DIR/quotes.txt" ]; then
    cp "$SELF_DIR/quotes.txt" "$DATA_DIR/quotes.txt"
  fi
  if [ ! -f "$CONF_DIR/termi.conf" ]; then
    cat > "$CONF_DIR/termi.conf" <<'EOF'
# termi configuration (zsh syntax; sourced by the termi script).
# Uncomment to override the defaults.
# TERMI_SOURCE=file          # file | api
# TERMI_API_URL=""           # plain-text endpoint, one quote per line
# TERMI_CACHE_TTL=86400      # seconds between API cache refreshes
# TERMI_QUOTES_FILE="$XDG_DATA_HOME/termi/quotes.txt"
EOF
  fi
  append_block "$HOME/.zshrc" zsh_snippet
  append_block "$HOME/.bashrc" bash_snippet
  # Never CREATE .bash_profile: its existence makes bash login shells skip
  # ~/.profile. Only hook it when the user already has one (macOS bash users).
  if [ -f "$HOME/.bash_profile" ]; then
    append_block "$HOME/.bash_profile" bash_snippet
  fi
  printf 'termi installed. Open a new terminal to see it.\n'
}

uninstall() {
  rm -f "$BIN_DIR/termi"
  remove_block "$HOME/.zshrc"
  remove_block "$HOME/.bashrc"
  remove_block "$HOME/.bash_profile"
  printf 'termi removed. Quotes and config kept in %s and %s\n' "$DATA_DIR" "$CONF_DIR"
}

case "${1:-}" in
  "")          install_files ;;
  --quotes)    if [ "$#" -ne 2 ]; then usage >&2; exit 2; fi
               merge_quotes "$2" ;;
  --uninstall) uninstall ;;
  -h|--help)   usage ;;
  *)           usage >&2; exit 2 ;;
esac

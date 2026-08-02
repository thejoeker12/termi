#!/bin/sh
# termi installer. POSIX sh on purpose: this script is what CHECKS for zsh,
# so it must run on machines that do not have zsh.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/termi"
# v1 kept quotes and a config file locally; both are gone, so uninstall clears them out.
LEGACY_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/termi"
LEGACY_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/termi"
MARK_START="# >>> termi >>>"
MARK_END="# <<< termi <<<"

usage() {
  cat <<'EOF'
Usage: install.sh [--uninstall]
  (no args)       install termi: script and shell hooks
  --uninstall     remove the script, shell hooks and cached quotes
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

install_files() {
  require_zsh
  mkdir -p "$BIN_DIR"
  cp "$SELF_DIR/bin/termi" "$BIN_DIR/termi"
  chmod 755 "$BIN_DIR/termi"
  append_block "$HOME/.zshrc" zsh_snippet
  append_block "$HOME/.bashrc" bash_snippet
  # Never CREATE .bash_profile: its existence makes bash login shells skip
  # ~/.profile. Only hook it when the user already has one (macOS bash users).
  if [ -f "$HOME/.bash_profile" ]; then
    append_block "$HOME/.bash_profile" bash_snippet
  fi
  printf 'termi installed. Open a new terminal twice: the first fetches the quotes, the second shows one.\n'
}

uninstall() {
  rm -f "$BIN_DIR/termi"
  remove_block "$HOME/.zshrc"
  remove_block "$HOME/.bashrc"
  remove_block "$HOME/.bash_profile"
  # Safe to delete outright: the quotes live in the bucket, nothing here is authored locally.
  rm -rf "$CACHE_DIR" "$LEGACY_DATA_DIR" "$LEGACY_CONF_DIR"
  printf 'termi removed.\n'
}

case "${1:-}" in
  "")          install_files ;;
  --uninstall) uninstall ;;
  -h|--help)   usage ;;
  *)           usage >&2; exit 2 ;;
esac

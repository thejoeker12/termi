#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

# --- Uninstall removes script, hooks and cache, keeps other rc content
sandbox
print -r -- "# my prompt setup" > "$HOME/.zshrc"
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "cached-quote" > "$XDG_CACHE_HOME/termi/quotes.txt"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
sh "$REPO_ROOT/install.sh" --uninstall > /dev/null
[[ -e "$HOME/.local/bin/termi" ]]; assert_eq 1 "$?" "script removed"
assert_contains "$(cat "$HOME/.zshrc")" "# my prompt setup" "user rc content kept"
assert_eq 0 "$(grep -cF '# >>> termi >>>' "$HOME/.zshrc")" "zshrc block removed"
assert_eq 0 "$(grep -cF '# >>> termi >>>' "$HOME/.bashrc")" "bashrc block removed"
[[ -e "$XDG_CACHE_HOME/termi" ]]; assert_eq 1 "$?" "cache removed"

# --- v1 left quotes and a config file behind; uninstall clears those too
sandbox
mkdir -p "$XDG_DATA_HOME/termi" "$XDG_CONFIG_HOME/termi"
print -r -- "old-quote" > "$XDG_DATA_HOME/termi/quotes.txt"
print -r -- "TERMI_SOURCE=file" > "$XDG_CONFIG_HOME/termi/termi.conf"
sh "$REPO_ROOT/install.sh" --uninstall > /dev/null
[[ -e "$XDG_DATA_HOME/termi" ]]; assert_eq 1 "$?" "legacy data dir removed"
[[ -e "$XDG_CONFIG_HOME/termi" ]]; assert_eq 1 "$?" "legacy config dir removed"

# --- Symlinked rc files survive install + uninstall (dotfile repos)
sandbox
mkdir -p "$SANDBOX/dotfiles"
print -r -- "# dotfiles zshrc" > "$SANDBOX/dotfiles/zshrc"
ln -s "$SANDBOX/dotfiles/zshrc" "$HOME/.zshrc"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
[[ -L "$HOME/.zshrc" ]]; assert_eq 0 "$?" ".zshrc still a symlink after install"
assert_contains "$(cat "$SANDBOX/dotfiles/zshrc")" "# >>> termi >>>" "block landed in the real file"
sh "$REPO_ROOT/install.sh" --uninstall > /dev/null
[[ -L "$HOME/.zshrc" ]]; assert_eq 0 "$?" ".zshrc still a symlink after uninstall"
assert_eq 0 "$(grep -cF '# >>> termi >>>' "$SANDBOX/dotfiles/zshrc")" "block removed from real file"
assert_contains "$(cat "$SANDBOX/dotfiles/zshrc")" "# dotfiles zshrc" "real file content kept"

# --- Bad arguments: usage on stderr, exit 2
out=$(sh "$REPO_ROOT/install.sh" --bogus 2>&1); st=$?
assert_eq 2 "$st" "unknown flag exits 2"
assert_contains "$out" "Usage:" "unknown flag prints usage"
out=$(sh "$REPO_ROOT/install.sh" --quotes q.txt 2>&1); st=$?
assert_eq 2 "$st" "retired --quotes flag exits 2"

# --- --help prints usage on stdout and exits 0
out=$(sh "$REPO_ROOT/install.sh" --help); st=$?
assert_eq 0 "$st" "--help exits 0"
assert_contains "$out" "--uninstall" "--help documents uninstall"

finish

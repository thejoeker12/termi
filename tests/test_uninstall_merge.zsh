#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

# --- Merge dedupes, drops blanks, keeps first-seen order
sandbox
mkdir -p "$XDG_DATA_HOME/termi"
print -l -- "alpha" "beta" > "$XDG_DATA_HOME/termi/quotes.txt"
print -l -- "beta" "gamma" "" "alpha" "delta" > "$SANDBOX/new.txt"
out=$(sh "$REPO_ROOT/install.sh" --quotes "$SANDBOX/new.txt"); st=$?
assert_eq 0 "$st" "--quotes exits 0"
assert_eq "$(print -l -- alpha beta gamma delta)" "$(cat "$XDG_DATA_HOME/termi/quotes.txt")" "merge dedupes and keeps order"

# --- Merge works before any install (creates the data dir)
sandbox
print -l -- "solo" > "$SANDBOX/new.txt"
sh "$REPO_ROOT/install.sh" --quotes "$SANDBOX/new.txt" > /dev/null
assert_eq "solo" "$(cat "$XDG_DATA_HOME/termi/quotes.txt")" "merge bootstraps quotes file"

# --- Missing merge file dies with exit 1
out=$(sh "$REPO_ROOT/install.sh" --quotes "$SANDBOX/absent.txt" 2>&1); st=$?
assert_eq 1 "$st" "missing merge file exits 1"
assert_contains "$out" "not found" "missing merge file explains itself"

# --- Uninstall removes script and hooks, keeps data and config, keeps other rc content
sandbox
print -r -- "# my prompt setup" > "$HOME/.zshrc"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
sh "$REPO_ROOT/install.sh" --uninstall > /dev/null
[[ -e "$HOME/.local/bin/termi" ]]; assert_eq 1 "$?" "script removed"
assert_contains "$(cat "$HOME/.zshrc")" "# my prompt setup" "user rc content kept"
assert_eq 0 "$(grep -cF '# >>> termi >>>' "$HOME/.zshrc")" "zshrc block removed"
assert_eq 0 "$(grep -cF '# >>> termi >>>' "$HOME/.bashrc")" "bashrc block removed"
assert_file_exists "$XDG_DATA_HOME/termi/quotes.txt" "quotes kept on uninstall"
assert_file_exists "$XDG_CONFIG_HOME/termi/termi.conf" "config kept on uninstall"

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
out=$(sh "$REPO_ROOT/install.sh" --quotes 2>&1); st=$?
assert_eq 2 "$st" "--quotes without file exits 2"

finish

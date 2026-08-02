#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

# --- Fresh install puts every artifact in place
sandbox
out=$(sh "$REPO_ROOT/install.sh" 2>&1); st=$?
assert_eq 0 "$st" "install exits 0"
assert_file_exists "$HOME/.local/bin/termi" "script installed"
[[ -x "$HOME/.local/bin/termi" ]]; assert_eq 0 "$?" "script is executable"
assert_file_exists "$XDG_DATA_HOME/termi/quotes.txt" "starter quotes installed"
assert_file_exists "$XDG_CONFIG_HOME/termi/termi.conf" "config seeded"
assert_contains "$(cat "$HOME/.zshrc")" "# >>> termi >>>" "zshrc hook added"
assert_contains "$(cat "$HOME/.bashrc")" "# >>> termi >>>" "bashrc hook added"

# --- Never create .bash_profile
[[ -e "$HOME/.bash_profile" ]]; assert_eq 1 "$?" "bash_profile not created"

# --- Re-run is idempotent (exactly one marker block per rc file)
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
assert_eq 1 "$(grep -cF '# >>> termi >>>' "$HOME/.zshrc")" "zshrc has exactly one block after rerun"
assert_eq 1 "$(grep -cF '# >>> termi >>>' "$HOME/.bashrc")" "bashrc has exactly one block after rerun"

# --- Existing .bash_profile gets the hook
sandbox
touch "$HOME/.bash_profile"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
assert_contains "$(cat "$HOME/.bash_profile")" "# >>> termi >>>" "existing bash_profile gets hook"

# --- Existing user quotes are never overwritten
sandbox
mkdir -p "$XDG_DATA_HOME/termi"
print -r -- "my-own-quote" > "$XDG_DATA_HOME/termi/quotes.txt"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
assert_eq "my-own-quote" "$(cat "$XDG_DATA_HOME/termi/quotes.txt")" "existing quotes preserved"

# --- Existing config is never overwritten
sandbox
mkdir -p "$XDG_CONFIG_HOME/termi"
print -r -- "TERMI_SOURCE=api" > "$XDG_CONFIG_HOME/termi/termi.conf"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
assert_eq "TERMI_SOURCE=api" "$(cat "$XDG_CONFIG_HOME/termi/termi.conf")" "existing config preserved"

# --- Refuses without zsh: PATH of symlinked tools, minus zsh
sandbox
nozsh="$SANDBOX/nozsh"
mkdir -p "$nozsh"
for t in sh awk grep mkdir cp chmod cat rm mktemp wc tr dirname pwd touch env; do
  p=$(whence -p "$t") && ln -s "$p" "$nozsh/$t"
done
out=$(env PATH="$nozsh" sh "$REPO_ROOT/install.sh" 2>&1); st=$?
assert_eq 1 "$st" "missing zsh exits 1"
assert_contains "$out" "requires zsh" "missing zsh explains itself"

finish

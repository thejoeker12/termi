#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

# Full user flow in a sandbox: install, then open interactive shells.
# The sandbox curl shim fails, so the cache stays exactly as seeded here.
sandbox
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "zen-quote-42" > "$XDG_CACHE_HOME/termi/quotes.txt"   # single known quote

out=$(zsh -ic 'exit' 2>/dev/null)
assert_contains "$out" "zen-quote-42" "new interactive zsh prints a quote"

out=$(bash -ic 'exit' 2>/dev/null)
assert_contains "$out" "zen-quote-42" "new interactive bash prints a quote"

# Non-interactive shells stay silent (scp/sftp safety)
out=$(zsh -c 'true' 2>/dev/null)
assert_eq "" "$out" "non-interactive zsh is silent"
out=$(bash -c 'true' 2>/dev/null)
assert_eq "" "$out" "non-interactive bash is silent"

# Login bash where .bash_profile sources .bashrc: exactly ONE quote (TERMI_RAN)
print -r -- 'source ~/.bashrc' > "$HOME/.bash_profile"
sh "$REPO_ROOT/install.sh" > /dev/null 2>&1   # rerun hooks the now-existing .bash_profile
out=$(bash -lic 'exit' 2>/dev/null)
assert_eq 1 "$(print -r -- "$out" | grep -cF 'zen-quote-42')" "login bash prints exactly one quote"

finish

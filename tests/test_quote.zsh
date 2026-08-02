#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"
sandbox
source "$REPO_ROOT/bin/termi"   # loads functions only; main is exec-guarded

qf="$SANDBOX/q.txt"
print -l -- "alpha" "beta" "gamma" > "$qf"

out=$(termi_pick_random_line "$qf")
assert_contains "alpha beta gamma" "$out" "picks a line that exists in the file"

# Collect draws via redirection, NOT $(...): zsh's RANDOM does not advance
# the parent shell's generator inside a command-substitution subshell, so a
# $(...) loop would return the identical line every iteration.
# All lines reachable: P(missing one of 3 in 100 draws) ~ 3*(2/3)^100 ~ 1e-17
for i in {1..100}; do
  termi_pick_random_line "$qf" >> "$SANDBOX/draws.txt"
done
assert_eq 3 "$(sort -u "$SANDBOX/draws.txt" | grep -c .)" "all lines reachable over 100 draws"

# Blank lines are never printed
print -l -- "" "solo" "" "" > "$SANDBOX/blanks.txt"
for i in {1..25}; do
  termi_pick_random_line "$SANDBOX/blanks.txt" >> "$SANDBOX/bdraws.txt"
done
assert_eq "solo" "$(sort -u "$SANDBOX/bdraws.txt")" "blank lines are skipped"

# Missing file: status 1, no output
out=$(termi_pick_random_line "$SANDBOX/nope.txt"); st=$?
assert_eq 1 "$st" "missing file returns 1"
assert_eq "" "$out" "missing file prints nothing"

# Executed as a script: reads the default XDG location
mkdir -p "$XDG_DATA_HOME/termi"
print -r -- "only-quote" > "$XDG_DATA_HOME/termi/quotes.txt"
out=$("$REPO_ROOT/bin/termi"); st=$?
assert_eq "only-quote" "$out" "prints quote from default XDG data path"
assert_eq 0 "$st" "exits 0 on success"

# No quotes installed: silent success (must never break shell startup)
sandbox
out=$("$REPO_ROOT/bin/termi"); st=$?
assert_eq 0 "$st" "missing quotes file exits 0"
assert_eq "" "$out" "missing quotes file prints nothing"

finish

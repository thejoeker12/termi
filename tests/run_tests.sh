#!/usr/bin/env zsh
# Runs every tests/test_*.zsh in its own zsh process so state cannot leak.
emulate -L zsh
# Resolve before the cd: the :A modifier is relative to the current directory,
# so reading $0 after cd'ing would double up the tests/ component.
typeset here="${0:A:h}"
export REPO_ROOT="${here:h}"
cd -- "$here"
typeset -i failed=0
for t in test_*.zsh(N); do
  print -r -- "== $t"
  zsh "$t" || failed=1
done
if (( failed )); then
  print -r -- "TESTS FAILED"
  exit 1
fi
print -r -- "All tests passed"

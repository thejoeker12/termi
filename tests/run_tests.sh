#!/usr/bin/env zsh
# Runs every tests/test_*.zsh in its own zsh process so state cannot leak.
emulate -L zsh
cd -- "${0:A:h}"
export REPO_ROOT="${0:A:h:h}"
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

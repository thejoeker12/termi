# Test helpers — source from each test file. No framework, zero deps.
emulate -L zsh
typeset -gi TESTS_RUN=0 TESTS_FAILED=0

# Isolate every filesystem effect from the real $HOME.
sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
}

assert_eq() {  # expected actual label
  (( ++TESTS_RUN ))
  if [[ "$1" == "$2" ]]; then
    print -r -- "  ok: $3"
  else
    (( ++TESTS_FAILED ))
    print -r -- "  FAIL: $3"
    print -r -- "    expected: $1"
    print -r -- "    actual:   $2"
  fi
}

assert_contains() {  # haystack needle label
  (( ++TESTS_RUN ))
  if [[ "$1" == *"$2"* ]]; then
    print -r -- "  ok: $3"
  else
    (( ++TESTS_FAILED ))
    print -r -- "  FAIL: $3"
    print -r -- "    output:  $1"
    print -r -- "    missing: $2"
  fi
}

assert_file_exists() {  # path label
  (( ++TESTS_RUN ))
  if [[ -e "$1" ]]; then
    print -r -- "  ok: $2"
  else
    (( ++TESTS_FAILED ))
    print -r -- "  FAIL: $2 (missing: $1)"
  fi
}

finish() {
  print -r -- "  ($TESTS_RUN checks, $TESTS_FAILED failed)"
  (( TESTS_FAILED == 0 ))
}

# Replace curl with a fake that logs calls and emits a fixture.
# Usage: make_curl_shim FIXTURE [EXITCODE]
make_curl_shim() {
  local fixture="$1" rc="${2:-0}"
  SHIM_DIR="$SANDBOX/shim"
  mkdir -p "$SHIM_DIR"
  {
    print -r -- '#!/bin/sh'
    print -r -- "echo called >> '$SANDBOX/curl-calls.log'"
    if (( rc == 0 )); then
      print -r -- "cat '$fixture'"
    fi
    print -r -- "exit $rc"
  } > "$SHIM_DIR/curl"
  chmod 755 "$SHIM_DIR/curl"
  export PATH="$SHIM_DIR:$PATH"
}

curl_calls() {  # number of times the shim was invoked
  if [[ -f "$SANDBOX/curl-calls.log" ]]; then
    wc -l < "$SANDBOX/curl-calls.log" | tr -d ' '
  else
    print 0
  fi
}

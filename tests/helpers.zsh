# Test helpers — source from each test file. No framework, zero deps.
emulate -L zsh
typeset -gi TESTS_RUN=0 TESTS_FAILED=0

# Every test file resolves the app via $REPO_ROOT. run_tests.sh exports it,
# but default it from this file's own location so a single test file can also
# be run directly: zsh tests/test_quote.zsh
: ${REPO_ROOT:="${0:A:h:h}"}
export REPO_ROOT

# Captured before any shim lands on PATH, so repeated sandbox calls in one test
# file cannot stack shim directories.
: ${TERMI_REAL_PATH:=$PATH}

# Isolate every filesystem effect from the real $HOME.
sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
  # The bucket URL is hardcoded in the app, so every run tries to fetch it.
  # Every sandbox therefore starts with a curl that fails: no test can reach
  # the real network even if it forgets to call make_curl_shim.
  SHIM_DIR="$SANDBOX/shim"
  mkdir -p "$SHIM_DIR"
  write_curl_shim "" 22 0
  export PATH="$SHIM_DIR:$TERMI_REAL_PATH"
}

write_curl_shim() {  # fixture exitcode delay — internal
  local fixture="$1" rc="$2" delay="$3"
  {
    print -r -- '#!/bin/sh'
    print -r -- "echo called >> '$SANDBOX/curl-calls.log'"
    (( delay > 0 )) && print -r -- "sleep $delay"
    (( rc == 0 )) && print -r -- "cat '$fixture'"
    print -r -- "exit $rc"
  } > "$SHIM_DIR/curl"
  chmod 755 "$SHIM_DIR/curl"
}

# Replace the sandbox curl with a fake that logs calls and emits a fixture.
# Usage: make_curl_shim FIXTURE [EXITCODE] [DELAY_SECONDS]
make_curl_shim() {
  write_curl_shim "$1" "${2:-0}" "${3:-0}"
}

curl_calls() {  # number of times the shim was invoked
  if [[ -f "$SANDBOX/curl-calls.log" ]]; then
    wc -l < "$SANDBOX/curl-calls.log" | tr -d ' '
  else
    print 0
  fi
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

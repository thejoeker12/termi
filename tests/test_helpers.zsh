#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

sandbox
assert_file_exists "$HOME" "sandbox creates a HOME"
assert_contains "$HOME" "$SANDBOX" "HOME lives inside the sandbox"
assert_eq "a b" "a b" "assert_eq matches equal strings"
assert_contains "hello world" "lo wo" "assert_contains finds substrings"

# The default shim is the guard against a stray test hitting the real bucket
assert_eq "$SHIM_DIR/curl" "$(whence -p curl)" "sandbox puts a curl shim first on PATH"
curl https://example.invalid/ > /dev/null 2>&1
assert_eq 22 "$?" "default shim fails instead of reaching the network"
assert_eq 1 "$(curl_calls)" "shim calls are counted"

finish

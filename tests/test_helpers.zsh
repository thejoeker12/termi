#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

sandbox
assert_file_exists "$HOME" "sandbox creates a HOME"
assert_contains "$HOME" "$SANDBOX" "HOME lives inside the sandbox"
assert_eq "a b" "a b" "assert_eq matches equal strings"
assert_contains "hello world" "lo wo" "assert_contains finds substrings"
finish

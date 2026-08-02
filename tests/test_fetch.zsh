#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"
zmodload zsh/datetime

setup_fetch_env() {  # fresh sandbox with a fixture ready to serve
  sandbox
  fixture="$SANDBOX/api-fixture.txt"
  print -l -- "api-one" "api-two" > "$fixture"
  cache="$XDG_CACHE_HOME/termi/quotes.txt"
}

wait_for_cache() {  # poll for the background refresh (max ~5s)
  for i in {1..50}; do
    [[ -s "$cache" ]] && return 0
    sleep 0.1
  done
  return 1
}

# --- Nothing cached yet: silent, but the background fetch fills the cache
setup_fetch_env
make_curl_shim "$fixture"
out=$("$REPO_ROOT/bin/termi"); st=$?
assert_eq 0 "$st" "first ever run exits 0"
assert_eq "" "$out" "first ever run prints nothing"
wait_for_cache
assert_file_exists "$cache" "background refresh populated the cache"
assert_eq "$(cat "$fixture")" "$(cat "$cache")" "cache matches the bucket response"

# --- Cache present: prints from it
out=$("$REPO_ROOT/bin/termi")
assert_contains "api-one api-two" "$out" "prints from cache once populated"

# --- Every run refetches: no TTL, a seconds-old cache is still refreshed
rm -f "$SANDBOX/curl-calls.log"
"$REPO_ROOT/bin/termi" > /dev/null
for i in {1..50}; do
  (( $(curl_calls) > 0 )) && break
  sleep 0.1
done
assert_eq 1 "$(curl_calls)" "a fresh cache is refetched anyway"

# --- Old cache prints instantly and is replaced in the background
setup_fetch_env
make_curl_shim "$fixture"
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "stale-quote" > "$cache"
out=$("$REPO_ROOT/bin/termi")
assert_eq "stale-quote" "$out" "prints the cache it had, not the one being fetched"
for i in {1..50}; do
  [[ "$(cat "$cache")" != "stale-quote" ]] && break
  sleep 0.1
done
assert_eq "$(cat "$fixture")" "$(cat "$cache")" "cache refreshed in background"

# --- Failed fetch never clobbers a good cache
setup_fetch_env
make_curl_shim "$fixture" 22
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "good-cache" > "$cache"
out=$("$REPO_ROOT/bin/termi")
for i in {1..50}; do
  (( $(curl_calls) > 0 )) && break
  sleep 0.1
done
sleep 0.3   # grace period for any (wrong) cache write to land
assert_eq "good-cache" "$(cat "$cache")" "failed fetch keeps the old cache"
assert_eq "good-cache" "$out" "still prints from surviving cache"

# --- No curl on the box: silent no-op, cache still printed
setup_fetch_env
mkdir -p "$XDG_CACHE_HOME/termi" "$SANDBOX/nocurl"
print -r -- "cached-quote" > "$cache"
zshbin=$(whence -p zsh)
out=$(PATH="$SANDBOX/nocurl" "$zshbin" "$REPO_ROOT/bin/termi"); st=$?
assert_eq 0 "$st" "missing curl exits 0"
assert_eq "cached-quote" "$out" "missing curl still prints the cache"

# --- A slow endpoint must not delay the shell
setup_fetch_env
make_curl_shim "$fixture" 0 3
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "instant-quote" > "$cache"
start=$EPOCHREALTIME
out=$("$REPO_ROOT/bin/termi")
elapsed=$(( EPOCHREALTIME - start ))
assert_eq "instant-quote" "$out" "slow fetch still prints immediately"
(( elapsed < 1 )); assert_eq 0 "$?" "3s fetch does not block the run (took ${elapsed}s)"

finish

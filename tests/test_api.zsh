#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

setup_api_env() {  # fresh sandbox with api config + file fallback + curl shim fixture
  sandbox
  mkdir -p "$XDG_CONFIG_HOME/termi" "$XDG_DATA_HOME/termi"
  print -r -- "file-quote" > "$XDG_DATA_HOME/termi/quotes.txt"
  fixture="$SANDBOX/api-fixture.txt"
  print -l -- "api-one" "api-two" > "$fixture"
  {
    print -r -- "TERMI_SOURCE=api"
    print -r -- "TERMI_API_URL=\"https://example.invalid/quotes\""
  } > "$XDG_CONFIG_HOME/termi/termi.conf"
  cache="$XDG_CACHE_HOME/termi/api-quotes.txt"
}

wait_for_cache() {  # poll for the background refresh (max ~5s)
  for i in {1..50}; do
    [[ -s "$cache" ]] && return 0
    sleep 0.1
  done
  return 1
}

# --- No cache yet: fall back to file, background-refresh the cache
setup_api_env
make_curl_shim "$fixture"
out=$("$REPO_ROOT/bin/termi"); st=$?
assert_eq 0 "$st" "api source exits 0"
assert_eq "file-quote" "$out" "falls back to file before first fetch"
wait_for_cache
assert_file_exists "$cache" "background refresh populated the cache"
assert_eq "$(cat "$fixture")" "$(cat "$cache")" "cache matches API response"

# --- Cache present: prints from cache
out=$("$REPO_ROOT/bin/termi")
assert_contains "api-one api-two" "$out" "prints from cache once populated"

# --- Fresh cache: no refetch
rm -f "$SANDBOX/curl-calls.log"
out=$("$REPO_ROOT/bin/termi")
sleep 0.5
assert_eq 0 "$(curl_calls)" "fresh cache does not refetch"

# --- Stale cache: still prints instantly from old cache, refreshes in background
setup_api_env
make_curl_shim "$fixture"
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "stale-quote" > "$cache"
touch -t 202001010000 "$cache"
out=$("$REPO_ROOT/bin/termi")
assert_eq "stale-quote" "$out" "stale cache still prints instantly"
wait_for_cache
for i in {1..50}; do
  [[ "$(cat "$cache")" != "stale-quote" ]] && break
  sleep 0.1
done
assert_eq "$(cat "$fixture")" "$(cat "$cache")" "stale cache refreshed in background"

# --- Failed fetch never clobbers a good cache
setup_api_env
make_curl_shim "$fixture" 22
mkdir -p "$XDG_CACHE_HOME/termi"
print -r -- "good-cache" > "$cache"
touch -t 202001010000 "$cache"
out=$("$REPO_ROOT/bin/termi")
for i in {1..50}; do
  (( $(curl_calls) > 0 )) && break
  sleep 0.1
done
sleep 0.3   # grace period for any (wrong) cache write to land
assert_eq "good-cache" "$(cat "$cache")" "failed fetch keeps the old cache"
assert_eq "good-cache" "$out" "still prints from surviving cache"

# --- Empty API URL: never calls curl
setup_api_env
make_curl_shim "$fixture"
print -r -- "TERMI_SOURCE=api" > "$XDG_CONFIG_HOME/termi/termi.conf"
out=$("$REPO_ROOT/bin/termi")
sleep 0.5
assert_eq 0 "$(curl_calls)" "empty TERMI_API_URL never invokes curl"
assert_eq "file-quote" "$out" "empty URL falls back to file"

finish

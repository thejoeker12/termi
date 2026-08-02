#!/usr/bin/env zsh
source "${0:A:h}/helpers.zsh"

sandbox
mkdir -p "$XDG_CONFIG_HOME/termi"
alt="$SANDBOX/alt.txt"
print -r -- "custom-quote" > "$alt"
print -r -- "TERMI_QUOTES_FILE=\"$alt\"" > "$XDG_CONFIG_HOME/termi/termi.conf"
assert_eq "custom-quote" "$("$REPO_ROOT/bin/termi")" "TERMI_QUOTES_FILE override honoured"

# Config defaults when no config file exists
sandbox
source "$REPO_ROOT/bin/termi"
assert_eq "file" "$TERMI_SOURCE" "default source is file"
assert_eq "" "$TERMI_API_URL" "default API URL is empty"
assert_eq 86400 "$TERMI_CACHE_TTL" "default TTL is 86400"
assert_eq "$XDG_DATA_HOME/termi/quotes.txt" "$TERMI_QUOTES_FILE" "default quotes path is XDG"

finish

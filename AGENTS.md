# AGENTS.md

## What this is

`termi` prints a random quote when a new interactive terminal opens. Quotes come from one hardcoded
S3 URL and nowhere else. Target platforms: macOS and Linux, zero runtime installs. The app is zsh;
the installer is POSIX sh (it must run on machines that do not have zsh, in order to say so).

## Status

v2 is the current shape: bucket-only, no config, no local quote file. It replaced v1's two-source
design (local `quotes.txt` plus optional API cache selected by `termi.conf`). Removed in v2 and not
coming back: `TERMI_SOURCE`, `TERMI_API_URL`, `TERMI_CACHE_TTL`, `TERMI_QUOTES_FILE`, the config file
itself, the bundled `quotes.txt`, and `install.sh --quotes`. `main` is the working branch and the
only branch.

The suite is the gate for any change: `tests/run_tests.sh` must print `All tests passed` and exit 0.
It is currently 69 checks across 6 files.

Deliberately out of scope — do not add without being asked: local quote files, config of any kind,
fish support, `--help`/`--version` on `termi` itself, JSON parsing, quote categories or weighting,
Windows.

Two things tests cannot cover, so verify by hand. After touching `install.sh` or the rc snippets:
run `sh install.sh` on a real machine, open a new terminal tab, and confirm a quote prints before
the prompt (the first tab after a fresh install is silent — it only populates the cache). After
touching output formatting: the green branch only fires on a real tty, and every test captures
output, so look at it in a terminal (or drive it through `zsh/zpty`).

## Layout

| Path | Purpose |
|---|---|
| `bin/termi` | The app. zsh. All functions prefixed `termi_`. `TERMI_URL` at the top is the single quote source. Quotes print in ANSI green (`termi_green` / `termi_print_quote`), plain when stdout is not a tty. Sourced-safe: `source bin/termi` loads functions without running `termi_main` (guarded by `zsh_eval_context`). |
| `install.sh` | POSIX sh. Install / `--uninstall`. |
| `README.md` | User-facing docs: install, where quotes come from, S3 hosting recipe, addquote script, uninstall. Keep in step with behaviour changes — it is the only doc a human reads. |
| `tests/` | Plain zsh tests, no framework. `tests/run_tests.sh` runs each `test_*.zsh` in its own zsh process. |
| `tests/helpers.zsh` | Sourced first by every test file. Provides `sandbox`, `assert_eq`, `assert_contains`, `assert_file_exists`, `finish`, `make_curl_shim`, `curl_calls`, and defaults `$REPO_ROOT`. |

Test files: `test_helpers.zsh`, `test_quote.zsh` (line picking, cache reads), `test_fetch.zsh`
(refresh behaviour), `test_install.zsh`, `test_uninstall.zsh`, `test_integration.zsh`.

## Installed layout

- Script: `~/.local/bin/termi`
- Cache: `${XDG_CACHE_HOME:-~/.cache}/termi/quotes.txt` — the only state, and disposable
- Shell hooks: guarded blocks between `# >>> termi >>>` and `# <<< termi <<<` in `~/.zshrc`,
  `~/.bashrc`, and `~/.bash_profile` (the last only if it already existed — never create it; its
  existence changes bash login behaviour).

There is no config file and no data dir. `uninstall` deletes the cache and also clears the v1
leftovers `${XDG_DATA_HOME:-~/.local/share}/termi` and `${XDG_CONFIG_HOME:-~/.config}/termi`.

## Commands

```sh
sh install.sh                      # install script + rc hooks (no network, no config)
sh install.sh --uninstall          # remove script, rc blocks, cache and v1 leftovers
tests/run_tests.sh                 # run all tests
zsh tests/test_quote.zsh           # run one test file
```

`install.sh` exit codes: 0 ok, 1 environment error (no zsh), 2 usage error (unknown flag; usage goes
to stderr). `--uninstall` deliberately skips the zsh check — it only removes things.

## Configuration

None. The bucket URL is the constant `TERMI_URL` at the top of `bin/termi`
(`https://jl-termi-quotes-2026.s3.eu-west-2.amazonaws.com/quotes.txt`). Changing buckets means
editing that line and rerunning `sh install.sh`. Do not reintroduce a config file, an env override,
or an installer flag for it — the whole point of v2 is that there is one knob and it lives in the
source.

## Fetch design

Every run fires a disowned background `curl` (10s timeout, output to /dev/null) that refreshes the
cache via atomic tmp-file + `mv`, then prints from whatever the previous run left in the cache.
There is no TTL and no freshness check — refresh happens unconditionally. A failed or empty fetch
never clobbers a good cache. Shell startup is never blocked by the network. A machine with no cache
yet prints nothing. The endpoint contract is plain text, one quote per line.

## Hard rules

- **Portability (BSD + GNU userlands):** never `sed -i`, never `stat`, never `readlink -f`. Use
  awk + `cat tmp > file` for in-place edits.
- **rc files may be symlinks:** append with `>>`, rewrite with `cat "$tmp" > "$file"`, never `mv`
  onto an rc file.
- **Never break shell startup:** every `bin/termi` failure path exits 0 silently, and the fetch is
  always backgrounded and disowned.
- **Interactive-only guard, no tty test:** snippets check `[[ -o interactive ]]` (zsh) / `case $- in
  *i*)` (bash). This keeps scp/sftp safe and keeps `zsh -ic` testable through a pipe. The `[[ -t 1 ]]`
  in `termi_print_quote` is not an exception to this — it decides *how* the quote is printed, never
  *whether*. A pipe still gets the quote, just without the escape codes.
- **`TERMI_RAN` guard in the bash snippet is deliberately not exported** — it dedupes
  `.bash_profile`-sources-`.bashrc` within one process while letting nested/tmux shells print.
- **Tests:** sandboxed `$HOME` via `sandbox` in `tests/helpers.zsh`. Because the URL is hardcoded,
  `sandbox` also installs a failing `curl` shim on `PATH`; `make_curl_shim` overwrites it when a
  test wants a fixture. Never touch the real `$HOME` or the network. Reach the app through
  `$REPO_ROOT/bin/termi`, never a relative path — `sandbox` does not change directory, but tests run
  from wherever the caller stood.
- **`${0:A}` resolves against the current directory**, so capture paths from `$0` *before* any `cd`.
  `run_tests.sh` got this wrong once and silently pointed `$REPO_ROOT` at `tests/`.
- **Everything in the repo is tracked.** The v1 `spec.md` and `plan.md` were deleted in v2 and
  `.gitignore` covers only `.DS_Store`. Any doc worth keeping, this file included, belongs in the
  commit that changes it.

## Keep this file current

Update AGENTS.md in the same change whenever anything here goes stale (commands, layout, config
keys, rules). If a change doesn't affect it, say so explicitly in your summary.

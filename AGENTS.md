# AGENTS.md

## What this is

`termi` prints a random quote when a new interactive terminal opens. Target platforms: macOS and Linux, zero runtime installs. The app is zsh; the installer is POSIX sh (it must run on machines that do not have zsh, in order to say so). See `plan.md` for the full implementation plan and `spec.md` for the original spec (both local-only, see the ignore rule below).

## Status

v1 is complete and merged into `main` (PR #1, squash-merged as `feat: v1`). The whole plan shipped: quote engine, cached API source, installer with merge and uninstall, and 69 checks across 7 test files. `main` is the working branch and the only branch — `dev-v1` was squash-merged and has been deleted.

The suite is the gate for any change: `tests/run_tests.sh` must print `All tests passed` and exit 0.

Deliberately out of scope — do not add without being asked: fish support, `--help`/`--version` on `termi` itself, JSON API parsing, quote categories or weighting, Windows.

One thing tests cannot cover, so verify by hand after touching `install.sh` or the rc snippets: run `sh install.sh` on a real machine, open a new terminal tab, and confirm a quote prints before the prompt.

## Layout

| Path | Purpose |
|---|---|
| `bin/termi` | The app. zsh. All functions prefixed `termi_`. Sourced-safe: `source bin/termi` loads functions without running `termi_main` (guarded by `zsh_eval_context`). |
| `install.sh` | POSIX sh. Install / `--quotes FILE` merge / `--uninstall`. |
| `quotes.txt` | Bundled starter quotes, one per line, `Quote — Author`. |
| `README.md` | User-facing docs: install, config keys, API mode, S3 hosting recipe, uninstall. Keep in step with behaviour changes — it is the only doc a human reads. |
| `tests/` | Plain zsh tests, no framework. `tests/run_tests.sh` runs each `test_*.zsh` in its own zsh process. |
| `tests/helpers.zsh` | Sourced first by every test file. Provides `sandbox`, `assert_eq`, `assert_contains`, `assert_file_exists`, `finish`, `make_curl_shim`, `curl_calls`, and defaults `$REPO_ROOT`. |

## Installed layout (XDG on both OSes)

- Script: `~/.local/bin/termi`
- Quotes: `${XDG_DATA_HOME:-~/.local/share}/termi/quotes.txt`
- Config: `${XDG_CONFIG_HOME:-~/.config}/termi/termi.conf` (zsh syntax, sourced by the app; created once, never overwritten)
- API cache: `${XDG_CACHE_HOME:-~/.cache}/termi/api-quotes.txt`
- Shell hooks: guarded blocks between `# >>> termi >>>` and `# <<< termi <<<` in `~/.zshrc`, `~/.bashrc`, and `~/.bash_profile` (the last only if it already existed — never create it; its existence changes bash login behaviour).

## Commands

```sh
sh install.sh                      # install everything
sh install.sh --quotes new.txt     # merge quotes (dedupes, drops blanks, keeps order)
sh install.sh --uninstall          # remove script + rc blocks; keeps quotes/config
tests/run_tests.sh                 # run all tests
zsh tests/test_quote.zsh           # run one test file
```

`install.sh` exit codes: 0 ok, 1 environment/input error (no zsh, missing quotes file), 2 usage error (unknown or incomplete flag; usage goes to stderr). `--quotes` and `--uninstall` deliberately skip the zsh check — they only move text around.

## Config keys (all optional; defaults in `bin/termi`)

- `TERMI_SOURCE` — `file` (default) or `api`
- `TERMI_API_URL` — plain-text endpoint, one quote per line (same format as quotes.txt); empty default
- `TERMI_CACHE_TTL` — seconds before the API cache is considered stale (default 86400)
- `TERMI_QUOTES_FILE` — override quotes file path

## API design

`TERMI_SOURCE=api` prints from the local cache (instant), falling back to the quotes file when no cache exists yet. If the cache is stale, a disowned background `curl` (10s timeout, output to /dev/null) refreshes it via atomic tmp-file + `mv`. A failed or empty fetch never clobbers a good cache. Shell startup is never blocked by the network. The plain-text contract means the file parser and API parser are the same function.

## Hard rules

- **Portability (BSD + GNU userlands):** never `sed -i`, never `stat`, never `readlink -f`. Use zsh `zstat` for mtimes; awk + `cat tmp > file` for in-place edits.
- **rc files may be symlinks:** append with `>>`, rewrite with `cat "$tmp" > "$file"`, never `mv` onto an rc file.
- **Never break shell startup:** every `bin/termi` failure path exits 0 silently.
- **Interactive-only guard, no tty test:** snippets check `[[ -o interactive ]]` (zsh) / `case $- in *i*)` (bash). This keeps scp/sftp safe and keeps `zsh -ic` testable through a pipe.
- **`TERMI_RAN` guard in the bash snippet is deliberately not exported** — it dedupes `.bash_profile`-sources-`.bashrc` within one process while letting nested/tmux shells print.
- **Tests:** sandboxed `$HOME` via `sandbox` in `tests/helpers.zsh`; network is faked with a curl PATH shim (`make_curl_shim`); never touch the real `$HOME` or the network. Reach the app through `$REPO_ROOT/bin/termi`, never a relative path — `sandbox` does not change directory, but tests run from wherever the caller stood.
- **`${0:A}` resolves against the current directory**, so capture paths from `$0` *before* any `cd`. `run_tests.sh` got this wrong once and silently pointed `$REPO_ROOT` at `tests/`.
- `spec.md` and `plan.md` are gitignored — keep them current on disk, but do not commit them. Everything else, this file included, is tracked and belongs in the commit that changes it.

## Keep this file current

Update AGENTS.md in the same change whenever anything here goes stale (commands, layout, config keys, rules). If a change doesn't affect it, say so explicitly in your summary.

# termi

Prints a random quote when you open a new terminal.

```
Last login: Sun Aug  2 21:18:33 on ttys004
Talk is cheap. Show me the code. — Linus Torvalds
~ $
```

That's the whole thing. It runs on macOS and Linux, needs nothing installed beyond zsh, and is
written so that a broken config, a missing file, or a dead network can never stop your shell from
starting.

## Install

```sh
git clone https://github.com/thejoeker12/termi.git
cd termi
sh install.sh
```

Open a new terminal and you'll see a quote.

The installer is POSIX sh rather than zsh on purpose: it's the thing that checks whether you have
zsh, so it has to run on machines that don't. If zsh is missing it tells you how to get it and exits
1.

What lands where:

| Path | What |
|---|---|
| `~/.local/bin/termi` | The script |
| `~/.local/share/termi/quotes.txt` | Your quotes |
| `~/.config/termi/termi.conf` | Config, created once and never overwritten |
| `~/.cache/termi/api-quotes.txt` | Downloaded quotes, when using a URL |

`XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` are respected if you set them. You don't need
`~/.local/bin` on your `PATH` — the shell hook calls the script by absolute path.

The hook itself goes into `~/.zshrc` and `~/.bashrc`, wrapped in markers so it can be removed
cleanly:

```sh
# >>> termi >>>
[[ -o interactive && -x "$HOME/.local/bin/termi" ]] && "$HOME/.local/bin/termi"
# <<< termi <<<
```

`~/.bash_profile` also gets a hook, but only if you already had one. Creating it would change how
bash login shells behave — bash reads `~/.bash_profile` *instead of* `~/.profile` when it exists —
and silently rearranging your login sequence isn't a reasonable price for a quote.

## Adding your own quotes

One quote per line. The convention is `Quote — Author`, but nothing enforces it, so put whatever you
like on a line.

```sh
sh install.sh --quotes my-quotes.txt
```

That merges rather than replaces: blank lines are dropped, duplicates are skipped, and existing
order is kept. Safe to run repeatedly with the same file.

Or just edit `~/.local/share/termi/quotes.txt` directly.

## Configuration

Everything is optional. `~/.config/termi/termi.conf` is zsh syntax and is sourced by the script, so
it's shell, not INI.

| Key | Default | What |
|---|---|---|
| `TERMI_SOURCE` | `file` | `file` or `api` |
| `TERMI_API_URL` | empty | Plain-text URL, one quote per line |
| `TERMI_CACHE_TTL` | `86400` | Seconds before downloaded quotes are refetched |
| `TERMI_QUOTES_FILE` | `$XDG_DATA_HOME/termi/quotes.txt` | Where the quotes live |

## Pulling quotes from a URL

Point termi at any URL that returns plain text, one quote per line — the same format as
`quotes.txt`. There's no JSON parsing, which means the file parser and the network parser are
literally the same function.

```sh
TERMI_SOURCE=api
TERMI_API_URL="https://example.com/quotes.txt"
```

Your shell never waits on the network. termi prints from a local cache immediately, and if that
cache is older than `TERMI_CACHE_TTL` it forks a disowned `curl` to refresh it for next time. So:

- The first terminal you open after switching to `api` prints from your local `quotes.txt`, because
  the cache doesn't exist yet. Every terminal after that uses the downloaded list.
- Quotes can be up to one TTL stale. That's the trade for never blocking startup.
- A failed or empty download leaves the existing cache alone (it writes to a temp file and moves it
  into place), so an endpoint that goes down means stale quotes, not broken quotes.
- If `curl` isn't installed, the refresh quietly does nothing.

To skip the first-run wait, prime the cache yourself:

```sh
mkdir -p ~/.cache/termi
curl -fsSL "$TERMI_API_URL" > ~/.cache/termi/api-quotes.txt
```

The endpoint needs to return 200 with a non-empty body within 10 seconds. There's no support for
auth headers, so anything private needs the credential in the URL.

## Sharing one quote list across machines

An S3 object URL is already a single GET endpoint, so you don't need an API in front of it. Create a
bucket, make just the one key public, and point every machine at it.

```sh
BUCKET=your-unique-bucket-name
REGION=eu-west-2

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"   # omit this flag in us-east-1

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Block Public Access vetoes the policy below unless these two are relaxed.
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(cat <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow","Principal":"*","Action":"s3:GetObject",
  "Resource":"arn:aws:s3:::$BUCKET/quotes.txt"}]}
EOF
)"

aws s3 cp quotes.txt "s3://$BUCKET/quotes.txt" --content-type "text/plain; charset=utf-8"
```

The policy grants read on `quotes.txt` alone, not `/*`, so nothing else you put in the bucket is
exposed. Set `--content-type` or S3 stores it as `binary/octet-stream`, which curl ignores but a
browser will download instead of display; the `charset=utf-8` keeps em dashes intact.

Your `TERMI_API_URL` is then `https://$BUCKET.s3.$REGION.amazonaws.com/quotes.txt`.

Two things worth knowing. That URL is genuinely public — anyone who has it can read the file and
cost you requests and egress, so pick an unguessable bucket name and never put anything private in
there. And if two machines read-append-write at the same moment, the later write wins outright;
versioning gets the lost quote back, but nothing prevents the clash.

To append from a machine, give it credentials scoped to that single key
(`s3:GetObject` and `s3:PutObject` on `arn:aws:s3:::BUCKET/quotes.txt`) and then:

```sh
#!/bin/sh
# addquote "Quote — Author"
BUCKET=your-unique-bucket-name
tmp=$(mktemp)
aws s3 cp "s3://$BUCKET/quotes.txt" "$tmp" --quiet
printf '%s\n' "$1" >> "$tmp"
awk 'NF && !seen[$0]++' "$tmp" > "$tmp.clean"
aws s3 cp "$tmp.clean" "s3://$BUCKET/quotes.txt" \
  --content-type "text/plain; charset=utf-8" --quiet
rm -f "$tmp" "$tmp.clean"
```

That `awk` line is the same merge logic `install.sh --quotes` uses locally, so both routes behave
identically.

## Uninstall

```sh
sh install.sh --uninstall
```

Removes the script and strips the marker blocks out of your rc files, leaving the rest of those
files untouched. Your quotes and config stay put, so reinstalling picks up where you left off.
Delete `~/.local/share/termi` and `~/.config/termi` by hand if you want them gone.

## How it works

Roughly 70 lines of zsh. The interesting decisions:

**It cannot break your shell.** Every failure path in `bin/termi` returns 0 without printing.
Missing quotes file, unreadable cache, no curl, garbage config — you get no quote, not an error.

**It checks for an interactive shell, not a tty.** The hooks test `[[ -o interactive ]]` in zsh and
`case $- in *i*)` in bash. Testing for a tty would be wrong: scp and sftp sessions would still be
safe, but the quote would vanish whenever output is piped, which also makes the thing untestable.

**Portable across BSD and GNU userlands.** No `sed -i`, no `stat`, no `readlink -f` — those differ
between macOS and Linux. Timestamps come from zsh's `zstat`, in-place edits go through awk plus
`cat tmp > file`.

**Your rc files might be symlinks.** Common with dotfile repos. So termi appends with `>>` and
rewrites with `cat "$tmp" > "$file"`, never `mv`, which would replace the symlink with a regular
file and quietly detach it from your dotfiles.

**Two shells opening in the same second get different quotes.** The RNG is seeded from PID xor
epoch, and because zsh's `RANDOM` is only 15 bits, two draws are combined so lists longer than
32767 lines stay reachable.

## Development

```sh
tests/run_tests.sh            # everything
zsh tests/test_quote.zsh      # one file
```

69 checks across 7 files, no framework — each `test_*.zsh` runs in its own zsh process. Tests
sandbox `$HOME` and fake the network with a `curl` shim on `PATH`, so they never touch your real
home directory or make a request. `All tests passed` and exit 0 is the gate for any change.

One thing the tests can't cover: whether a quote actually appears when a real terminal starts. After
touching `install.sh` or the rc snippets, run `sh install.sh` on a real machine and open a new tab.

`bin/termi` is safe to source — `source bin/termi` loads the functions without running anything,
which is how the tests get at the internals.

## Not doing

Deliberately out of scope: fish support, `--help`/`--version` on `termi` itself, JSON API parsing,
quote categories or weighting, and Windows.

## Requirements

zsh for the app. bash or zsh as your interactive shell. curl only if you use a URL. macOS or Linux.

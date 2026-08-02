# termi

Prints a random quote when you open a new terminal.

```
Last login: Sun Aug  2 21:18:33 on ttys004
Talk is cheap. Show me the code. — Linus Torvalds
~ $
```

That's the whole thing. Quotes live in one S3 bucket, every machine reads from it, and there is
nothing to configure. It runs on macOS and Linux, needs nothing installed beyond zsh, and is written
so that a dead network can never stop your shell from starting.

## Install

```sh
git clone https://github.com/thejoeker12/termi.git
cd termi
sh install.sh
```

The first terminal you open downloads the quotes and prints nothing; every one after that prints a
quote.

The installer is POSIX sh rather than zsh on purpose: it's the thing that checks whether you have
zsh, so it has to run on machines that don't. If zsh is missing it tells you how to get it and exits
1.

What lands where:

| Path | What |
|---|---|
| `~/.local/bin/termi` | The script |
| `~/.cache/termi/quotes.txt` | Last download from the bucket |

That's all of it — no config file, no local quote list. `XDG_CACHE_HOME` is respected if you set it.
You don't need `~/.local/bin` on your `PATH` — the shell hook calls the script by absolute path.

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

## Where the quotes come from

One URL, hardcoded at the top of `bin/termi`:

```sh
TERMI_URL="https://jl-termi-quotes-2026.s3.eu-west-2.amazonaws.com/quotes.txt"
```

It returns plain text, one quote per line. The convention is `Quote — Author`, but nothing enforces
it. To use a different bucket, edit that line and run `sh install.sh` again.

Every run fires a `curl` in the background to refresh the cache, and prints from the copy the
previous run downloaded. Your shell never waits on the network. So:

- Quotes are one terminal behind the bucket. That's the trade for never blocking startup.
- A failed or empty download leaves the existing cache alone (it writes to a temp file and moves it
  into place), so an endpoint that goes down means yesterday's quotes, not broken quotes.
- If `curl` isn't installed, the refresh quietly does nothing.
- A machine that has never managed a successful download prints nothing at all.

## Hosting the bucket

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

Your `TERMI_URL` is then `https://$BUCKET.s3.$REGION.amazonaws.com/quotes.txt`.

Two things worth knowing. That URL is genuinely public — anyone who has it can read the file and
cost you requests and egress, so pick an unguessable bucket name and never put anything private in
there. And every terminal you open is a GET, so keep an eye on it if you live in tmux.

## Adding a quote

Quotes only exist in the bucket, so adding one means writing to the bucket. Give the machine
credentials scoped to that single key (`s3:GetObject` and `s3:PutObject` on
`arn:aws:s3:::BUCKET/quotes.txt`) and then:

```sh
#!/bin/sh
# addquote "Quote — Author"
BUCKET=jl-termi-quotes-2026
tmp=$(mktemp)
aws s3 cp "s3://$BUCKET/quotes.txt" "$tmp" --quiet
printf '%s\n' "$1" >> "$tmp"
awk 'NF && !seen[$0]++' "$tmp" > "$tmp.clean"
aws s3 cp "$tmp.clean" "s3://$BUCKET/quotes.txt" \
  --content-type "text/plain; charset=utf-8" --quiet
rm -f "$tmp" "$tmp.clean"
```

The `awk` line drops blanks and duplicates. If two machines read-append-write at the same moment the
later write wins outright; versioning gets the lost quote back, but nothing prevents the clash.

## Uninstall

```sh
sh install.sh --uninstall
```

Removes the script, strips the marker blocks out of your rc files, and deletes the cache. Nothing of
yours is in there — the quotes are in the bucket — so it's a complete removal. It also clears the
`~/.local/share/termi` and `~/.config/termi` directories that older versions used.

## How it works

Roughly 50 lines of zsh. The interesting decisions:

**It cannot break your shell.** Every failure path in `bin/termi` returns 0 without printing. No
cache, unreadable cache, no curl, dead bucket — you get no quote, not an error.

**The fetch never blocks.** The refresh runs as a disowned background job with its output sent to
`/dev/null`, so it neither delays your prompt nor holds open the stdout pipe of a `$(termi)`.

**It checks for an interactive shell, not a tty.** The hooks test `[[ -o interactive ]]` in zsh and
`case $- in *i*)` in bash. Testing for a tty would be wrong: scp and sftp sessions would still be
safe, but the quote would vanish whenever output is piped, which also makes the thing untestable.

**Portable across BSD and GNU userlands.** No `sed -i`, no `stat`, no `readlink -f` — those differ
between macOS and Linux.

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

67 checks across 6 files, no framework — each `test_*.zsh` runs in its own zsh process. Tests
sandbox `$HOME` and put a failing `curl` shim on `PATH` for every sandbox, so a test can never reach
the real bucket even if it forgets to fake the network. `All tests passed` and exit 0 is the gate
for any change.

One thing the tests can't cover: whether a quote actually appears when a real terminal starts. After
touching `install.sh` or the rc snippets, run `sh install.sh` on a real machine and open a new tab.

`bin/termi` is safe to source — `source bin/termi` loads the functions without running anything,
which is how the tests get at the internals.

## Not doing

Deliberately out of scope: local quote files, config of any kind, fish support, `--help`/`--version`
on `termi` itself, JSON parsing, quote categories or weighting, and Windows.

## Requirements

zsh for the app. bash or zsh as your interactive shell. curl. macOS or Linux.

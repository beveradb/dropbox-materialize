# dropbox-materialize

`dbx-materialize` is a macOS CLI that forces Dropbox **online-only** files to download, so
scripts, `ffprobe`, `cp`, `scp`, etc. see real bytes instead of 0-byte stubs.

```bash
dbx-materialize "~/Dropbox/Music/song.flac"     # one file (blocks until local)
dbx-materialize -j 8 "Projects/Big Folder"       # whole folder, 8 parallel
dbx-materialize -s some/folder                      # status only: what's online-only?
```

`materialize` is installed as a short alias for the same binary.

## Why this exists

Dropbox online-only files (legacy **Smart Sync**) are 0-byte
placeholders tagged with a `com.dropbox.placeholder` xattr. A plain `cat`/`cp`/`read()` returns
0 bytes and **does not trigger a download**. Only an `NSFileCoordinator` *coordinated read* (what
apps do when they open a file) makes Dropbox fault the file in. This tool performs that read and
blocks until the file is fully local, then verifies it's no longer a placeholder.

It also detects macOS File Provider "dataless" files (`SF_DATALESS`, e.g. iCloud Drive), so it
works there too.

## Install

```bash
git clone https://github.com/beveradb/dropbox-materialize.git
cd dropbox-materialize
./install.sh            # swiftc build -> build/, symlinks into ~/.local/bin
```

Requires Xcode command-line tools (`swiftc`). Re-run `./install.sh` after changing `src/main.swift`.

## Usage

```
dbx-materialize [options] <path>...

  -s, --status        report online-only vs local; download nothing
  -j, --jobs N        parallel downloads (default 4)
  -f, --min-free GB   skip files once free disk is below GB (default 5)
  -q, --quiet         only print failures and the summary
  -h, --help / -V, --version
```

Paths may be files or directories (recursed; `.DS_Store` and `.dropbox*` skipped), absolute,
relative, or `~`-prefixed. Works from any cwd.

Output is one line per file on stdout (`FAIL` lines on stderr), then a summary on stderr:

| Tag | Meaning |
|-----|---------|
| `OK` | was online-only, now downloaded (size shown) |
| `LOCAL` | already local, nothing done |
| `ONLINE` | online-only (`--status` mode only) |
| `FLOOR` | skipped: free disk below `--min-free` |
| `FAIL` | coordination/read error, or still a placeholder afterwards |

Exit code: `0` all good · `1` any `FAIL`/`FLOOR`/missing path · `2` bad usage.

## Freeing the space again (no programmatic evict)

Legacy Smart Sync has **no API to make files online-only again** —
`NSFileProviderManager.domains()` is empty, so File Provider eviction can't see the files.
To reclaim disk: Finder → select files/folder → right-click → Dropbox → **Make Online-Only**.

`experimental/evict.swift` documents the File Provider eviction approach that *would* work if
Dropbox is ever migrated to the macOS File Provider build (`~/Library/CloudStorage/Dropbox*`).
It is not built or installed.

## Caveats

- Smart Sync placeholders report size 0, so sizes are unknown until downloaded and the
  `--min-free` floor is checked against current free space before each file starts (a single huge
  file can still dip below it). Use a generous floor or `-j 1` for very large batches.
- Requires the Dropbox desktop app to be running and signed in.
- Real 0-byte local files (no placeholder xattr) correctly report `LOCAL`.

## Tests

```bash
bash tests/smoke.sh     # CLI parsing, relative paths, recursion, exit codes, simulated placeholder
```

A real placeholder can't be faked. To test end-to-end, run `dbx-materialize -s` on a Dropbox folder,
pick a small `ONLINE` file, materialize it, then make it online-only again in Finder.

## History

Extracted from `nomadkaraoke/kjbox` `scripts/original_vocals/local_clone/materialize.swift`
(kjbox PR #178, Jul 2026), where it fed original-mix audio to the KJ device. That copy is a
single-file, single-path version; this repo is the maintained, globally installed one.

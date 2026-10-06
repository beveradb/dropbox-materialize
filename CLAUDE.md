# dropbox-materialize: notes for Claude

## Using the tool (from any project or terminal)

`dbx-materialize` (alias `materialize`) is on PATH via `~/.local/bin`. Use it **whenever you need
to read a file under `~/AB Dropbox/` (Andrew's Dropbox root; note the space, it's not
`~/Dropbox`) that may be online-only.** Signs: `ls -la` shows size `0`, `xattr` lists
`com.dropbox.placeholder`, or ffprobe/unzip/cp reports an empty or invalid file.

```bash
dbx-materialize -s <file-or-dir>          # check first: lists ONLINE vs LOCAL, downloads nothing
dbx-materialize <file>...                 # download; blocks until local; exit 0 = success
dbx-materialize -j 8 -q <dir>             # whole folder, parallel, only failures + summary
```

- `cat`/`cp`/`open()` do **not** download placeholders. Always materialize before reading.
- Sizes are unknown until downloaded (Smart Sync stubs report 0). Before materializing large
  trees, check `df -h ~` and keep the default `--min-free 5` floor or raise it.
- The tool can't make files online-only again. After a big batch, tell Andrew to free the space
  in Finder → right-click → Dropbox → **Make Online-Only**. Don't attempt to delete files to
  reclaim space.
- Don't bulk-download large media without checking with Andrew first, because disk on this Mac is
  often tight.

## Working on this repo

- Single source file `src/main.swift` (Foundation only, no package manager). Build and install with
  `./install.sh` (outputs `build/dbx-materialize`, symlinked into `~/.local/bin`, so rebuilding
  updates the global command in place).
- Test: `bash tests/smoke.sh`. For a real end-to-end check, materialize one small `ONLINE` file
  from `~/AB Dropbox` (see README).
- `experimental/evict.swift` is reference only (File Provider eviction, a no-op on legacy Smart
  Sync). Don't install it.
- Keep README.md's usage table in sync with `usage` in `main.swift`.

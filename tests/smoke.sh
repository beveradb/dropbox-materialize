#!/usr/bin/env bash
# Smoke tests that need no real Dropbox placeholder: CLI parsing, local-file
# detection, relative paths, directory recursion, exit codes, simulated placeholder.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/build/dbx-materialize"
[ -x "$BIN" ] || swiftc -O "$REPO/src/main.swift" -o "$BIN"

fails=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/d/sub"; echo hello > "$T/d/a.txt"; echo world > "$T/d/sub/b.txt"

check "help exits 0"           '"$BIN" --help >/dev/null'
check "no args exits 2"        '"$BIN" >/dev/null 2>&1; [ $? -eq 2 ]'
check "bad option exits 2"     '"$BIN" --nope x >/dev/null 2>&1; [ $? -eq 2 ]'
check "local file is LOCAL"    '"$BIN" "$T/d/a.txt" 2>/dev/null | grep -q "^LOCAL"'
check "relative path works"    '(cd "$T/d" && "$BIN" a.txt 2>/dev/null | grep -q "^LOCAL  *$T/d/a.txt")'
check "dir recursion"          '[ "$("$BIN" -s "$T/d" 2>/dev/null | grep -c "^LOCAL")" -eq 2 ]'
check "missing path exits 1"   '"$BIN" "$T/nope" >/dev/null 2>&1; [ $? -eq 1 ]'
check "quiet hides LOCAL"      '[ -z "$("$BIN" -q "$T/d" 2>/dev/null)" ]'

# Simulated placeholder: tagging a real file with the Dropbox xattr makes it
# report ONLINE in --status mode (we can't fake an actual Dropbox download).
xattr -w com.dropbox.placeholder 1 "$T/d/a.txt"
check "xattr => ONLINE status" '"$BIN" -s "$T/d/a.txt" 2>/dev/null | grep -q "^ONLINE"'
check "floor skips + exits 1"  '"$BIN" -f 999999 "$T/d/a.txt" 2>/dev/null | grep -q "^FLOOR"; "$BIN" -f 999999 "$T/d/a.txt" >/dev/null 2>&1; [ $? -eq 1 ]'

echo; [ "$fails" -eq 0 ] && echo "all smoke tests passed" || { echo "$fails failed"; exit 1; }

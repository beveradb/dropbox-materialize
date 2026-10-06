#!/usr/bin/env bash
# Build dbx-materialize and symlink it onto PATH (~/.local/bin by default).
# Re-run after pulling changes. Usage: ./install.sh [bin_dir]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${1:-$HOME/.local/bin}"

mkdir -p "$REPO/build" "$BIN_DIR"
swiftc -O "$REPO/src/main.swift" -o "$REPO/build/dbx-materialize"
ln -sf "$REPO/build/dbx-materialize" "$BIN_DIR/dbx-materialize"
ln -sf "$REPO/build/dbx-materialize" "$BIN_DIR/materialize"   # short alias

echo "installed: $BIN_DIR/dbx-materialize (+ alias 'materialize') -> $REPO/build/dbx-materialize"
command -v dbx-materialize >/dev/null || echo "WARNING: $BIN_DIR is not on your PATH"

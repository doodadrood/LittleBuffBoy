#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if command -v busted >/dev/null 2>&1; then
  echo "[LittleBuffBoy] Running unit tests with busted..."
  exec busted --pattern="_spec%.lua$" tests
elif command -v luajit >/dev/null 2>&1; then
  echo "[LittleBuffBoy] 'busted' not found on PATH; running Lua 5.1 compatible runner via luajit..."
  exec luajit tests/busted_runner.lua
elif command -v lua5.1 >/dev/null 2>&1; then
  echo "[LittleBuffBoy] 'busted' not found on PATH; running Lua 5.1 compatible runner via lua5.1..."
  exec lua5.1 tests/busted_runner.lua
else
  echo "ERROR: Neither busted, luajit, nor lua5.1 was found on PATH." >&2
  exit 1
fi

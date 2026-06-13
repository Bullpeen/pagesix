#!/usr/bin/env bash
#
# Provision a self-contained Lua toolchain for the fast inner dev loop
# (luacheck + the pure-Lua unit specs). It does NOT touch the system Lua, so a
# Homebrew `lua` upgrade can't break it again.
#
# Why Lua 5.1 (PUC) and not the system Lua?
#   * The project targets Lua 5.1 (see the rockspec: `lua ~> 5.1`); prod runs
#     OpenResty/LuaJIT, which is 5.1-compatible.
#   * The luarocks.org manifest is too large for LuaJIT's 65536-constant limit
#     under the luarocks version hererocks ships, so we use PUC 5.1 here.
#   * The full lapis/OpenResty integration suite is NOT run natively (it needs
#     ngx/resty + LuaJIT FFI); use Docker for that -- see README "Testing".
#
# Usage:  ./scripts/dev-setup.sh   (run from the repo root)
# Then:   source .lua/bin/activate && luacheck app && busted
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v hererocks >/dev/null 2>&1; then
  echo "==> installing hererocks (isolated Lua/LuaRocks provisioner)"
  if command -v pipx >/dev/null 2>&1; then
    pipx install hererocks
  else
    pip3 install --user hererocks
  fi
fi

echo "==> building ./.lua (PUC Lua 5.1 + LuaRocks)"
hererocks .lua -l 5.1 -r 3.8.0

# shellcheck disable=SC1091
source .lua/bin/activate

echo "==> installing test/lint toolchain"
luarocks install busted
luarocks install luacheck
luarocks install luacov
luarocks install lua-cjson   # used by a couple of pure-Lua specs (e.g. read_json)

echo
echo "Done. Activate the env and run the fast loop with:"
echo "    source .lua/bin/activate"
echo "    luacheck app          # lint (matches CI)"
echo "    busted app/spec/sort_spec.lua   # pure-Lua unit specs"
echo
echo "Full lapis/OpenResty suite runs in Docker -- see README 'Testing'."

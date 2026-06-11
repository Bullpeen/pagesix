#!/usr/bin/env bash
set -e

# Export the LuaRocks search paths so config.lua can forward them into
# OpenResty's lua_package_path/cpath -- OpenResty's defaults do not include the
# LuaRocks tree, so without this the workers can't load lapis/lpeg/lsqlite3.
# (Dependencies themselves are installed at image-build time; see Dockerfile.)
eval "$(luarocks --lua-version=5.1 path)"
export LUA_PATH="$LUA_PATH;/usr/local/openresty/lualib/?.lua"

cd /var/www
exec lapis server "${LAPIS_ENV}"

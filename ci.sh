#!/bin/bash
set -e
set -o pipefail
set -o xtrace

eval $(luarocks --lua-version=5.1 path)
luarocks --lua-version=5.1 make pagesix-dev-1.rockspec

# add openresty
export LUA_PATH="$LUA_PATH;/usr/local/openresty/lualib/?.lua"

# setup busted to run with luajit provided by openresty
cat $(which busted) | sed 's/\/usr\/bin\/lua5\.1/\/usr\/local\/openresty\/luajit\/bin\/luajit/' > busted
chmod +x busted

make build
make test_db

echo 'user root;' >> spec_openresty/s2/nginx.conf

./busted -o utfTerminal
./busted -o utfTerminal spec_postgres/
./busted -o utfTerminal spec_mysql/
./busted -o utfTerminal spec_openresty/
./busted -o utfTerminal spec_cqueues/
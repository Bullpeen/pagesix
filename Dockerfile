# https://github.com/leafo/lapis-archlinux-docker/blob/master/lapis-archlinux-itchio/Dockerfile
FROM ghcr.io/leafo/lapis-archlinux-itchio:latest

# Environment
ENV LAPIS_ENV="development"

# app code and the SQLite data dir are mounted at runtime
VOLUME /var/data
VOLUME /var/www

# Install Lua dependencies at build time into the default (world-readable)
# LuaRocks tree. The previous build installed into `$HOME/.luarocks` (/root,
# mode 700), which the unprivileged nginx workers cannot read, so nothing
# loaded at runtime. Doing it at build time (instead of in the entrypoint) also
# means a fast container start and a useful image cache.
COPY pagesix-dev-1.rockspec /
RUN luarocks --lua-version=5.1 build --only-deps /pagesix-dev-1.rockspec \
 && luarocks --lua-version=5.1 install lpeg \
 && luarocks --lua-version=5.1 install lsqlite3 \
 && luarocks --lua-version=5.1 install markdown \
 && luarocks --lua-version=5.1 install busted \
 && luarocks --lua-version=5.1 install luacov

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

WORKDIR /var/www

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

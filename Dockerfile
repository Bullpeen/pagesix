# TODO move to leaner (alpine?) image
# https://github.com/leafo/lapis-archlinux-docker/blob/master/lapis-archlinux-itchio/Dockerfile
FROM ghcr.io/leafo/lapis-archlinux-itchio:latest

# RUN pacman -Sy sqlite --noconfirm && \
# 	(yes | pacman -Scc || :)

# Environment
ENV LAPIS_ENV="development"

# Prepare volumes
VOLUME /var/data
VOLUME /var/www

RUN eval $(luarocks --lua-version=5.1 path)
RUN export LUA_PATH="$LUA_PATH;/usr/local/openresty/lualib/?.lua"

# install lua dependencies
COPY pagesix-dev-1.rockspec /
RUN luarocks --lua-version=5.1 build --tree "$HOME/.luarocks" --only-deps /pagesix-dev-1.rockspec

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

WORKDIR /var/www

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

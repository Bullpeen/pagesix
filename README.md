# Page Six

A better social link-sharing site.

## TODO

- [ ] model relationships defined:
  * 1 User -> 1 Comment
  * many comments -> 1 Post
  * many posts -> 1 Subreddit
  * many subreddits -> 1 Subreddits listing
- [ ] add [Constraints](https://leafo.net/lapis/reference/models.html#constraints) to models (?)
- [ ] add table indexes (hot-sorted subreddit posts, homepage, user accounts)
- [ ] user accounts w/[CSRF](https://leafo.net/lapis/reference/utilities.html#csrf-protection )
- [ ] Individual Pages
  - [ ] `homepage`
  - [ ] `/subreddits/` `/subreddits/mine` listings pages
  - [ ] `subreddit` landing page
    - [ ] Sorting parameter (`/r/.../top/?t=year`, `/popular`, `new`, `rising`, `controversial`)
    - [ ] use [Pagination](https://leafo.net/lapis/reference/models.html#pagination)
  - [ ] `/r/.../submit` (per-subreddit)
  - [ ] `/login`, `/logout`, `/password`
  - [ ] `prefs`, `settings`
- [x] RSS feed import/sync (per-subreddit; live importer + in-process scheduler)
- [ ] API (https://reddit.com/dev/api/)

See [`TODO.md`](TODO.md) for the living roadmap, including the forum-generalization
work (RBAC, admin panel, tags, @mentions, reputation, …).

## Development

From the root directory:

Build:

```
docker build . -t pagesix
```

Run:

```
docker run \
    -dti \
    -v "./data:/var/data" \
    -v "./app:/var/www" \
    -e LAPIS_ENV="development" \
    -p 8080:80 \
    --name pagesix \
    --platform=linux/amd64 \
    -d pagesix
```

Run migrations to populate the DB

```
lapis migrate
```

(wait patiently) then, visit: http://localhost:8080/

## Testing & linting

There are two tiers. The project targets **Lua 5.1** (prod runs
OpenResty/LuaJIT); do **not** use a Homebrew system `lua` (now 5.5) for it — a
5.5 upgrade breaks `busted`/`luacheck`, and `luacheck` can't even parse under
5.5.

**Fast inner loop (native, no Docker)** — lint + the pure-Lua unit specs, in a
self-contained Lua 5.1 toolchain under `.lua/` (gitignored, never touches the
system Lua):

```
./scripts/dev-setup.sh            # one-time: builds .lua/ via hererocks
source .lua/bin/activate
luacheck app                      # the exact CI lint step (0 warnings / 0 errors)
busted app/spec/sort_spec.lua     # pure-Lua specs (no lapis/DB needed)
```

**Full suite (lapis + OpenResty + SQLite)** — the model/SQL and HTTP
integration specs need the OpenResty runtime (`ngx`, `resty.*`, LuaJIT FFI), so
they run inside the Docker image, the same way CI does:

```
docker build -t pagesix-test .
# Mount the repo at /src and run busted from there (it needs the root .busted
# config + spec/). Set the LuaRocks paths the way the entrypoint does so the
# workers find lapis/lsqlite3/etc.
docker run --rm -v "$PWD:/src" -w /src --entrypoint bash pagesix-test -lc \
  'eval "$(luarocks --lua-version=5.1 path)"; export LUA_PATH="$LUA_PATH;/usr/local/openresty/lualib/?.lua"; busted -o utfTerminal'
```

(The mount needs the repo dir to be in Docker Desktop's File Sharing list.)

CI (`.github/workflows/spec.yml`) runs `luacheck app` then `busted --coverage`
across the `5.1 / 5.4 / luajit` matrix, plus a Docker build/run job.

# Notes

* [Reddit Archive](https://github.com/reddit-archive/reddit) - for CSS and HTML inspiration
* Built using [Lapis](https://leafo.net/lapis/) and [OpenResty](https://openresty.org/) in [Lua v5.1](https://www.lua.org/manual/5.1/)

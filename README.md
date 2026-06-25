# Page Six

A better social link-sharing site.

## Status

A working, test-covered Reddit clone: browsing with all the sorts + time
windows, FTS5 search, voting, link/self posts, threaded comments, edit/delete,
subscriptions, saved/hidden posts, profiles + karma, reply notifications,
RSS in/out, bcrypt + CSRF auth, a forum-generalization layer (RBAC, an Admin
Control Panel, reputation, an approval queue, tags, @mentions, OAuth), a
[Reddit-flavoured JSON API](#api), and ops endpoints ([`/health`](#operations--observability)
+ Prometheus [`/metrics`](#operations--observability)).

[`TODO.md`](TODO.md) is the living roadmap and changelog of what's shipped;
[`CHANGELOG.md`](CHANGELOG.md) has the narrative history.

## API

A Reddit-flavoured JSON API lives under `/api`. Responses are Reddit "Thing"
envelopes — `{ "kind": "t3", "data": { … } }` for a link (`t1` comment, `t2`
account, `t5` subreddit) — and `{ "kind": "Listing", "data": { "children": […],
"after": …, "before": … } }` for a page. Each Thing carries Reddit's base36 `id`
/ `t?_<id>` fullname plus an opaque, stable `uuid` (a `public_id` minted with
sqlean's `uuid4()`).

- **Reads** (public): `GET /api/listing(/:sort)`, `/api/r/:sub(/:sort)`,
  `/api/r/:sub/about`, `/api/comments/:id` (link + nested comment tree),
  `/api/info?id=t3_…,t1_…`, `/api/search?q=`, `/api/subreddits(/:where)`,
  `/api/subreddits/search?q=`, `/api/user/:name/about`,
  `/api/username_available?user=`. Sorts (`hot`/`new`/`top`/`best`/
  `controversial`/`rising`), `?t=` time windows, and `?after`/`?before`/`?limit`
  cursor pagination are supported.
- **Account** (logged in): `GET /api/v1/me`, `/api/v1/me/karma`,
  `/api/me/saved`.
- **Writes** (logged in): `POST /api/vote` `{id, dir}`, `/api/save`,
  `/api/unsave`, `/api/hide`, `/api/unhide`, `/api/subscribe`, `/api/submit`,
  `/api/comment`, `/api/del`, `/api/editusertext`.

Writes authenticate with the browser session and the same CSRF token as the web
forms (sent as the `csrf_token` field or an `X-Csrf-Token` header); OAuth
bearer-token auth is a future addition.

## Operations & observability

- **`GET /health`** — JSON liveness/readiness probe: `{ "status": "ok", "db":
  "ok", … }` with `200`, or `503` if a trivial DB query fails.
- **`GET /metrics`** — Prometheus text exposition (v0.0.4). Content gauges
  (`pagesix_users`, `pagesix_posts`, `pagesix_comments`, `pagesix_votes`,
  `pagesix_subreddits`, `pagesix_posts_pending`, …) plus
  `pagesix_http_requests_total{status="2xx"}` counters accumulated in a
  cross-worker `metrics` shared dict.
- **Dashboards with graphs** — the Admin panel has a `/admin/stats` page
  (site-wide activity over 30 days + top subreddits) and each community's
  moderators get `/r/:sub/stats` (per-sub activity + top contributors). Charts
  are server-rendered inline SVG (no client JS), drawn from the
  `v_daily_activity` view and `utils/stats`.

See [`docs/sqlite-features.md`](docs/sqlite-features.md) for where SQLite
triggers/views (and why not stored procedures) back this logic.

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

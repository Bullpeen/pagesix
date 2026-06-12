# sqlean integration plan

Plan for adding [sqlean](https://github.com/nalgeon/sqlean) loadable SQLite
extensions. This is a **future infra task** — the payoff is modest and the cost
(cross-platform binary bundling + a connection hook) is real, so it's deferred
until a concrete need (typo-tolerant search is the most likely trigger).

## What we verified

- **Loading works.** Our `lsqlite3` (3.53) exposes `conn:load_extension(path)`
  at the C-API level, so we do **not** need the SQL-level
  `enable_load_extension` (which this build doesn't expose anyway).
- **Per-connection.** Extensions load onto a single connection. Lapis opens its
  connection with `sqlite3.open()` inside `lapis/db/sqlite.lua` (a module-local
  `active_connection`, not exported), and may reconnect per worker.
- **`crypto` is unnecessary.** Secure tokens come from the built-in
  `hex(randomblob(32))` — no extension needed. This removes `crypto` from scope.

## Module verdict (recap of TODO)

| Module | Verdict | Use |
| --- | --- | --- |
| `regexp` | useful | `regexp_substr(url, ...)` to extract `posts.domain` host in SQL |
| `fuzzy` | useful | `dlevenshtein`/`soundex` typo-tolerant search ranking over FTS5 |
| `crypto` | drop | built-in `randomblob`/`hex` already covers tokens |
| `text`, `stats`, `math` | minor | doable in Lua / already in `sort.lua` |
| `uuid`, `define` | maybe | external ids (future API), wrap `url_host` as a SQL func |
| `ipaddr`, `vsv`, `unicode`, `time`, `besttype` | skip | not this workload |

## Implementation steps

### 1. Bundle the binaries (Dockerfile)
- Pin a sqlean release; download the Linux x86-64 build (production target is
  amd64) into `/usr/local/lib/sqlean/`, verifying a checksum.
- Only fetch the modules we use (`regexp.so`, `fuzzy.so`) to keep the image
  small.
- Dev note: on arm64 macOS, grab the matching macOS build or rely on Docker.

### 2. Load on every connection (`init_by_lua`, once per worker)
Wrap `lsqlite3.open` so every connection Lapis opens auto-loads the modules.
This is connection-correct and needs no patch to Lapis itself:

```lua
-- in config/init, before any DB use
local lsqlite3 = require("lsqlite3")
local real_open = lsqlite3.open
local SQLEAN = "/usr/local/lib/sqlean/"
lsqlite3.open = function(...)
    local conn = real_open(...)
    if conn then
        for _, mod in ipairs({ "regexp", "fuzzy" }) do
            -- default entrypoint sqlite3_<mod>_init matches the filename
            pcall(function() conn:load_extension(SQLEAN .. mod) end)
        end
    end
    return conn
end
```

Guard with a capability flag (`pcall` already degrades gracefully if a `.so` is
absent) so the app still boots without the binaries — every feature below must
have a Lua fallback.

### 3. Use the modules (incremental, each behind a capability check)
- **`posts.domain`** — optionally a generated column
  `GENERATED ALWAYS AS (regexp_substr(url, '://([^/]+)')) VIRTUAL`. Caveat:
  generated columns referencing an extension function require the extension
  loaded at both definition and query time; safer to keep the current Lua
  computation in `get_listing` and only add this if profiling shows it matters.
- **Search** — when an FTS5 query returns few hits, widen with a `dlevenshtein`
  pass on titles. Keep the FTS5 path as the default and fallback.

### 4. Tests + CI
- A spec asserting `load_extension` succeeds and `regexp_substr` /
  `dlevenshtein` return expected values, **skipped** when the `.so` is absent so
  the suite still runs on machines without the binaries.
- CI already builds the Docker image (which would carry the `.so`s), so the
  integration smoke covers the loaded path.

## Recommendation

Defer until typo-tolerant search is actually prioritized. At that point do steps
1–2 + the `fuzzy` search fallback only; treat the `regexp` domain column as a
separate, optional follow-up. `crypto` is off the table (built-ins suffice).

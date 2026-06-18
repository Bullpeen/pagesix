# sqlean integration plan

How we use [sqlean](https://github.com/nalgeon/sqlean) loadable SQLite
extensions. **Status: implemented.** The bundle is pinned at `0.28.3` in the
`Dockerfile` and loaded into Lapis's live connection per worker by
`src/utils/sqlite_ext.lua`. Every feature that uses it has a Lua fallback, so the
app still boots and the test suite still runs where the `.so` is absent.

Note on function names: the docs at nalgeon/sqlean (even the `0.28.3` tag) only
list the `fuzzy_*`-prefixed names (`fuzzy_jarowin`, `fuzzy_damlev`), but the
actual bundled `sqlean.so` *also* registers unprefixed aliases — `jaro_winkler`,
`dlevenshtein`, `levenshtein`, `soundex`, plus `regexp_like`/`regexp_substr`/
`regexp_replace`. We use the unprefixed names (verified by introspecting
`pragma_function_list` on the bundled `.so`).

## What we verified

- **Loading works.** Our `lsqlite3` (3.53) exposes `conn:load_extension(path)`
  at the C-API level, so we do **not** need the SQL-level
  `enable_load_extension` (which this build doesn't expose anyway).
- **Per-connection.** Extensions load onto a single connection. Lapis opens its
  connection with `sqlite3.open()` inside `lapis/db/sqlite.lua` (a module-local
  `active_connection`, not exported), and may reconnect per worker.
- **`crypto` is unnecessary.** Secure tokens come from the built-in
  `hex(randomblob(32))` — no extension needed. This removes `crypto` from scope.

## Module verdict (final)

| Module | Verdict | Use |
| --- | --- | --- |
| `fuzzy` | **adopted** | `jaro_winkler` for typo-tolerant subreddit search (`Forum:search`) and a word-level post-search fallback (`Posts:search`) |
| `regexp` | **adopted (light)** | `regexp_replace` normalizes title punctuation when splitting words for the fuzzy post-search fallback |
| `crypto` | dropped | tokens use `openssl.rand`; `randomblob`/`hex` cover the rest |
| `text`, `stats`, `math` | not adopted | doable in Lua / already in `sort.lua` |
| `uuid` | deferred | stable external ids, for the future API phase |
| `define` | not adopted | no reusable SQL func needed (the `url_host` column was dropped) |
| `ipaddr`, `vsv`, `unicode`, `time`, `besttype` | skip | not this workload |

## Implementation steps

### 1. Bundle the binary (Dockerfile) — done
The `Dockerfile` downloads the pinned `0.28.3` Linux x86-64 single-file bundle
(`sqlean.so`, all modules) to `/usr/local/lib/sqlite/`. One bundle is simpler
than cherry-picking per-module `.so`s and the size cost is negligible. The build
target is amd64; on arm64 macOS run the suite under Docker (see below).

### 2. Load onto Lapis's connection (per worker) — done
`src/utils/sqlite_ext.lua` loads the bundle onto the *same* lsqlite3 connection
Lapis runs queries on. Lapis keeps that connection as a private module upvalue
(`active_connection`) with no accessor, so the loader reaches it via
`debug.getupvalue` off one of the backend's closures, then calls
`conn:load_extension(path)`. It is invoked from `app.lua`'s `before_filter`, so
each nginx worker loads on its first request. `SQLITE_EXTENSIONS` overrides the
path list (empty = disabled). The loader never raises; every consumer below is
guarded by `sqlite_ext.load()` returning false and falls back to plain SQL/Lua.

### 3. The consumers (each behind a capability check) — done
- **`posts.domain`** — *not* a generated column. We store a normalized host in a
  real column (migration `[108]`) computed in Lua by `Posts:create` (socket.url),
  and backfilled. The generated-column form was declined: socket.url parses hosts
  more correctly than `regexp_substr`, and a generated column calling an extension
  function faults every INSERT (STORED) or SELECT (VIRTUAL) on a connection
  without the `.so` — i.e. the test suite and `lapis migrate`.
- **Subreddit search** (`Forum:search`) — `jaro_winkler` ranks typo-tolerant
  name matches; falls back to a plain `LIKE` substring match.
- **Post search** (`Posts:search` → `fuzzy_title_search`) — when FTS5 returns
  nothing, a word-level fuzzy pass: each title is normalized with
  `regexp_replace` and split into words (a recursive CTE), the query is split
  into words, and a post matches when some title word is `jaro_winkler`-close
  (≥ 0.85) to some query word. Word-level (not whole-string) matching is what
  makes it work on multi-word titles. Gated behind an empty FTS result, capped
  at 50 rows.

### 4. Tests + CI — done
- `sqlite_ext_spec`, `forum_search_spec`, and `posts_search_spec` assert the
  loaded behaviour; the extension-dependent examples mark themselves **pending**
  when the `.so` is absent so the generic-Lua `test` job still runs green.
- The `docker` CI job builds the production image (which carries the bundle) and
  runs the full suite, so the loaded path is exercised end to end.

## Outcome

`fuzzy` (+ a touch of `regexp`) is the payoff; `crypto` stays off the table
(built-ins suffice); `uuid` waits for the API phase. Everything else in the
bundle is loaded but unused — harmless, and there if a future need appears.

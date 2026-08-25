# TODO / Roadmap

What's planned, in progress, or known-incomplete.

**This is not a log of shipped work.** For that:

- [`CHANGELOG.md`](CHANGELOG.md) — what changed, newest first.
- [`docs/sqlite-features.md`](docs/sqlite-features.md) — why the schema and
  query decisions are what they are, including the ones we declined. Read this
  before changing the schema.
- [`docs/sqlean-plan.md`](docs/sqlean-plan.md) — per-module verdicts on the
  sqlean loadable extensions.

## In flight

Nothing.

## Next up

### Bearer-token auth for the JSON API

The largest functional gap. `/api` is complete and covered, but its **writes
authenticate with the browser session cookie plus the CSRF token**, so no
script, bot, or mobile client can use it — only a logged-in browser.

The existing `utils/oauth` is *inbound login* (GitHub/Google as identity
providers) and does not help here. This means issuing our own tokens: an
`api_tokens` table, `Authorization: Bearer` handled ahead of the global CSRF
filter in `app.lua`, and scopes.

### Awards / gold

The last cosmetic placeholder in the UI. Small, self-contained, low value.

## Known limits

Things that work but have a documented ceiling. None is a bug; each is a
deliberate stopping point, noted with what changing it would cost.

| Limit | Where | Notes |
| --- | --- | --- |
| Ranked-sort cursors cap at 1000 items | `utils/api_serialize` (`MAX_DEPTH`) | `hot`/`controversial`/`rising` rank on live vote counts, so a deep cursor into them cannot be exact however it is built. `new` uses real keyset pagination and has no cap. |
| Ranked listings still sort every matching row | `models/posts` `ORDER_BY` | `EXPLAIN QUERY PLAN` reports `USE TEMP B-TREE FOR ORDER BY` — the work moved into SQLite rather than disappearing. Making it index-driven means materializing scores, the counter-trigger trade `docs/sqlite-features.md` declined. |
| `Comments:by_user` fetches all of a user's comments | `models/comments` | The profile page slices them in Lua. The same treatment `Posts:get_listing` got would fix it. |
| `Posts:search` is hard-capped at 50 rows | `models/posts` | Fine for now; revisit if search gains cursors. |
| Several toggles still read-then-write | `Roles:assign`, `Subscriptions:toggle`, saved/hidden | Lower stakes than votes were — a duplicate there is idempotent, not score-changing — but UPSERT is the pattern to apply when they are next touched. |

## Deliberately out of scope

Recorded so they are not re-proposed:

- **Direct messages** between users.
- **Reddit surfaces with no backing data** — multis, wiki, modmail, friends,
  trophies, prefs, captcha.
- **Video embeds** (image links and thumbnails are supported).

# SQLite & Lapis features: where they fit our logic

A standing question on this project is *"can a database/framework feature do
this instead of hand-rolled Lua?"* This note records the verdicts so we don't
re-litigate them. Companion to `docs/sqlean-plan.md` (loadable extensions).

## Triggers — adopted where state must stay in lock-step

SQLite triggers are a good fit when a write must keep a derived structure
consistent and we never want application code to forget to do it.

- **FTS5 sync (adopted).** `posts_fts` is kept current by
  `posts_fts_ai/ad/au` triggers on `posts` (migration `[7]`): every
  insert/update/delete mirrors into the full-text index. This is the canonical
  trigger use — the search index can't drift from the table.
- **Denormalized counters (declined, for now).** We could maintain
  `forum.post_count` / per-day rollup tables with `AFTER INSERT/DELETE`
  triggers. We don't, because: (a) our counts must respect *soft* deletes
  (`deleted = 0`) and the approval queue (`approved = 1`), so a trigger would
  need to fire on those `UPDATE`s too and carry non-trivial conditions; (b) the
  hot listing path already gets its vote/comment counts from indexed subqueries
  (covering indexes, migrations `[5]`/`[6]`); and (c) the seed migrations bulk-
  insert thousands of rows, where per-row triggers add avoidable cost. The
  stats reads are infrequent (admin/mod dashboards, a scraped `/metrics`), so an
  aggregate-on-read is cheaper overall than taxing every write.

## Views — adopted for read-side aggregation

Earlier work **removed** the `v_hot_*` / `v_forum` listing views (see
`TODO.md`): the main listing varies per request (sort, time window, hidden/saved
filters), so a fixed view couldn't capture it and the FK/partial indexes serve
that path directly.

That objection does **not** apply to *static aggregations*, so we now use one:

- **`v_daily_activity` (adopted, migration `[110]`).** A view that buckets
  posts/comments/signups by `date(created_at)`. It backs the admin/mod activity
  graphs, `/metrics`, and `/health`. A view (vs. a trigger-maintained table) is
  right here because the data is purely read-side: the view is always consistent
  with zero write-path cost and no schema columns to backfill. Per-subreddit
  activity has no equivalent view — it needs a `sub_id` bind parameter, which a
  view can't take — so `Stats.for_sub` aggregates directly.

## Stored procedures — not available

SQLite has **no** stored procedures or server-side functions in the SQL/PSM
sense; logic lives in the application (or in C via loadable extensions — see the
sqlean bundle). Lapis's nearest equivalent is the **model** layer: methods like
`Votes:set`, `Posts:get_listing`, and the `Stats` helper are where reusable
query logic belongs. That's the convention we follow instead.

## Lapis features we lean on

- **`db.select` / `db.query` with bound params** for all dynamic SQL (never
  string-concatenate user input).
- **Models + relations** (`Model:extend`, `belongs_to`/`has_many`) for the CRUD
  surface; `constraints` for validation on create/update.
- **`respond_to`** for verb dispatch, **`@csrf`** for the global form guard,
  **etlua** layouts/partials, and **JSON responses** (`return { json = ... }`)
  for the API.
- **Migrations** as the single ordered source of schema truth (including the
  triggers and view above).

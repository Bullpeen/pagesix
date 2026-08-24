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

## Ranking and paging — adopted in SQL for the web listings

Listings used to fetch **every** matching post, rank them with `utils/sort`'s
comparators in Lua, and slice 25 out of the resulting array (`utils/paginate`).
Page 1 of a subreddit cost the same as page 40, and the cost grew with the
table.

`Posts:get_listing` now takes `sort`, `limit` and `offset` and does the work in
SQL (`ORDER_BY` in `models/posts.lua`). Each expression is *order-equivalent* to
the comparator it replaces, not a re-invention:

| sort | SQL | note |
| --- | --- | --- |
| `new` | `created_at DESC` | |
| `best` | `upvotes DESC` | |
| `top` | `(upvotes - downvotes) DESC` | |
| `rising` | net score ÷ hours since posting | |
| `hot` | `ABS(up - down) + strftime('%s', created_at)/45000.0` | drops the outer `log()` — it is monotonic and its argument is always > 0, so the order is unchanged |
| `controversial` | `POW(up + down, MIN/MAX)`, else 0 | needs SQLite's math functions (3.35+) |

`ORDER BY` reads the `upvotes`/`downvotes` **output aliases** instead of
repeating the correlated subqueries that compute them. Every ordering ends
`, a.id DESC`: without a total order, equal-ranked rows can swap between
requests and `LIMIT`/`OFFSET` paging then repeats or skips them. (The
`table.sort` this replaced was itself unstable, so tie order was already
arbitrary — just invisibly so.)

**What this does and does not buy.** Checked with `EXPLAIN QUERY PLAN`:

- `new` is satisfied by `posts_sub_id_created_at_idx` with **no** temp b-tree,
  so `LIMIT` genuinely stops early.
- The ranked sorts report `USE TEMP B-TREE FOR ORDER BY`: the vote subqueries
  are still evaluated for every matching row, and SQLite sorts them internally.

So ranked listings did not become O(page) — the ranking work moved *into*
SQLite (C, one bounded result set) instead of crossing into Lua as a full table
of allocated rows. Only the page plus one lookahead row is returned. Making the
ranked sorts index-driven would mean materializing scores (see the declined
counter-triggers above), which is a different trade.

`utils/paginate_db` asks for `per_page + 1` rows and treats the extra one as
"there is a next page", so a listing stays a single query with no companion
`COUNT(*)`. `utils/paginate` (array slicing) remains for callers that already
hold a full list — the profile's comment list, and the JSON API, whose
`after`/`before` cursors are resolved by scanning the ordered rows and so still
need them all.

## Partial indexes — adopted, including for uniqueness

A partial index (`CREATE INDEX ... WHERE <predicate>`) covers only the rows
matching its predicate. We use them two ways:

- **Hot-path filtering.** `posts_sub_id_created_at_idx` is built
  `WHERE deleted = 0 AND locked = 0`, so the listing scan never walks rows it
  would immediately discard.
- **Uniqueness over a nullable column (adopted, migration `[112]`).** `votes`
  was created with `UNIQUE(user_id, post_id, comment_id)`, which *reads* like
  "one vote per user per target" but is not: **SQLite treats NULLs as distinct
  in a UNIQUE index**, so for a post vote (`comment_id IS NULL`) the constraint
  never fires and one user could accumulate any number of votes on a post. The
  model's find-then-insert masked it single-threaded; production runs three
  nginx workers, where both can see "no existing row" and insert.

  The fix is two partial unique indexes, one per case, each over only the rows
  where the columns are non-NULL:

  ```sql
  CREATE UNIQUE INDEX votes_user_post_uniq
    ON votes (user_id, post_id)    WHERE comment_id IS NULL;
  CREATE UNIQUE INDEX votes_user_comment_uniq
    ON votes (user_id, comment_id) WHERE comment_id IS NOT NULL;
  ```

  General rule for this schema: **a UNIQUE constraint that includes a nullable
  column does not constrain the rows where that column is NULL.** Reach for a
  partial unique index instead.

## UPSERT — adopted where a read-then-write would race

`INSERT ... ON CONFLICT (...) DO UPDATE` performs the whole decision in one
statement, so concurrent workers cannot both pass a "does it exist?" check and
both insert. `Votes:cast`/`Votes:set` use it (`models/votes.lua`); the conflict
target repeats the partial index's `WHERE` clause, which SQLite requires in
order to match a partial index.

This is the preferred shape for any "create it, or update the one that's there"
path in this codebase. Several remain on find-then-write (`Roles:assign`,
`Subscriptions:toggle`, saved/hidden toggles); they are lower-stakes than votes
because a duplicate there is idempotent rather than score-changing, but the same
treatment applies when they are next touched.

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

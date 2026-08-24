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

## Referential actions — cascade for personal rows, never for content

Every foreign key into `users` was `NO ACTION`, so deleting an account meant
clearing each child table by hand first. Migration `[115]` splits the schema
along the line the product already draws:

- **Personal rows cascade** — `subscriptions`, `saved_posts`, `hidden_posts`,
  `notifications`, `password_resets`, `oauth_identities`, `roles`, `site_roles`.
  These belong to one person and mean nothing without them.
- **Authored content stays `NO ACTION`** — `posts`, `comments`, `votes`,
  `modlog`. Their policy is *reassignment* to the anonymous account, not
  deletion; a cascade would silently take other people's threads down with the
  author. With `NO ACTION`, deleting a user who still owns content **fails**,
  which is the correct outcome: something has to decide where it goes.

Two things to remember:

- **A cascade only fires when `PRAGMA foreign_keys = ON`**, which is a
  *per-connection* setting (`app.lua`'s `tune_sqlite`, and the spec helper). On
  a connection that missed it there is no cascade *and* no enforcement. That is
  why `Users:delete_account` still deletes the personal rows explicitly — the
  schema is a backstop, not the only copy of the policy.
- Adding a referential action needs the same table rebuild a `CHECK` does (see
  below); `notifications`, `roles` and `site_roles` are rebuilt in both `[114]`
  and `[115]`. Both run once, so the repeat costs nothing at runtime.

**Soft deletion** in this schema means `posts.deleted` / `comments.deleted` for
content and `forum.deleted_at` for subreddits. Users are *hard* deleted, so the
never-read `users.deleted_at` column was dropped in `[115]`.

## STRICT tables + CHECK constraints — adopted together

Every table is `STRICT` (the `strict` option on `schema.create_table`), so a
column's declared *type* is enforced rather than advisory. That says nothing
about a column's *values*, which is what `CHECK` adds — and until migration
`[114]` we had none, so `votes.upvote = 7` and `roles.role = 'wizard'` were both
storable. `upvote` was the one that mattered: it is read as
`CASE WHEN upvote = 1 THEN 1 ELSE -1 END`, so any stray value silently counted
as a downvote.

Constrained in `[114]`: `votes.upvote`, `notifications.kind` and `seen`,
`roles.role`, `site_roles.role`.

**Adding one costs a table rebuild.** SQLite has no
`ALTER TABLE ... ADD CONSTRAINT`, so the table is renamed, recreated with the
constraint, copied into, and dropped — the shape migration `[105]` already used.
Two consequences worth remembering next time:

- **Indexes live on the table**, so every index has to be recreated afterwards.
  `[114]` rebuilds `votes`, which carries five, including `[112]`'s partial
  uniques. The spec asserts they are all back.
- **Only leaf tables are cheap to rebuild.** All four here are leaves — no
  foreign key points *at* them — so the rebuild cannot orphan a reference.

`posts` and `comments` were left alone deliberately: they carry the FTS5 sync
triggers, so a rebuild has to reattach those too, and their remaining
unconstrained columns are boolean flags where a stray value is cosmetic rather
than score-changing. Prefer declaring `CHECK` on **new** tables, where it is
free.

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
`COUNT(*)`. `utils/paginate` (array slicing) remains for the profile's comment
list, which legitimately holds a full array.

### The JSON API's cursors

`/api` speaks Reddit's `after`/`before` **fullnames**, and `api_serialize.paginate`
finds the cursor row by scanning the ordered rows it was handed — so it can only
reach a row the caller actually fetched. Rather than fetch everything, the
endpoints size their window to the request (`S.window`):

- **no cursor** (every first page, and the common case): the page plus one
  lookahead row.
- **with a cursor**: `S.MAX_DEPTH` (1000) rows, which caps how deep a cursor can
  address.

**`new` skips the cap entirely.** Its key, `(created_at, id)`, never moves once a
post is written, so the database can seek straight to the cursor row with a
row-value comparison and return only the page:

```sql
WHERE (a.created_at, a.id) < (SELECT created_at, id FROM posts WHERE id = ?)
```

Comparing the whole key as a row value expresses "strictly past that row in this
order" in one shot, tiebreaker included. A cursor id that no longer exists makes
the subquery NULL, so the comparison is NULL and no rows come back — a stale
cursor reads as "nothing after this", which is exactly the wanted answer.
Walking *backwards* runs the comparison the other way in ascending order and
flips the rows, so the caller always sees one order.

The **ranked** sorts keep the window-and-cap treatment, and that is a property
of the data rather than a shortcut: `hot`, `controversial` and `rising` compute
rank from live vote counts, so a row's position moves between requests and a
cursor into one is approximate however it is implemented. Keyset would relocate
the inaccuracy, not remove it. Search engines and Reddit cap deep paging for the
same reason.

`Posts.KEYSET_SORTS` is the list, and `get_listing` **asserts** when a cursor is
passed with a sort that is not on it — an unstable-key cursor would fail
silently and subtly otherwise.

A cursor that is not in the window (past the cap, or a row since deleted) now
returns an **empty page**. It used to silently restart at the top, which left a
client paging in a loop without ever learning it had reached the end.

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

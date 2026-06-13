# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

This run took the PoC from a rough, non-booting prototype to a running,
test-covered Reddit clone. Highlights, newest first:

### Seed / migrations
- **`utils/read_json`** — migration `[13]` (seed initial subreddits) inlined an
  `io.open` + `cjson.decode` (with a `-- TODO figure out utils module` note);
  that's now a small `read_json(path)` util that tolerates a missing file
  (returns `nil`) and raises on malformed JSON so seeding fails loudly. Dropped
  the now-unused `io`/`cjson` requires from `migrations.lua`. Unit-tested in
  `spec/read_json_spec.lua` (3 pure-Lua specs). The sibling `misc.lua:84`
  `Users:select()` → `:count()` note was a non-fix (the rows are needed to pick
  a random user) — corrected in place rather than "done".

### Comments
- **Single-comment permalink view finished** — the `/r/:sub/comments/:post/_/:id`
  page was a static HTML mockup (hardcoded `COMMENT1`/`USER_NAME` placeholders)
  that ignored the actual comment. It now renders real data: a new
  `Comments:permalink_thread(id, context)` returns the focused comment plus its
  full reply subtree, optionally preceded by up to `?context=N` ancestor
  comments (a linear chain above it, depth-shifted), and `actions/comment.lua`
  renders it through the shared depth-aware comments fragment. Removed the dead
  `views/fragments/comment.etlua` mockup. (Refactored the shared row-enrichment
  and vote-count SQL out of `Comments:thread`/`by_user` so all three stay in
  sync.) Covered by 4 model specs (subtree/ancestor/clamp/unknown) + an HTTP
  test exercising `?context`.

### Pagination
- **Comment threads paginate** — a post's comment thread now pages off `?page=`
  (`COMMENTS_PER_PAGE = 25`). Paging is by **root comment**: a new
  `utils/paginate_thread` keeps each selected root together with its whole
  subtree, so a reply never gets orphaned onto a different page than its parent
  (a naive flat slice would). `actions/post.lua` no longer loads the full,
  unbounded thread.
- **User profiles paginate** — `actions/user.lua` pages a user's posts and
  comments off a shared `?page=`; the nav advances while *either* list still has
  more. Both reuse the existing `page_nav` fragment (rendered on the post and
  profile pages).
- **New `spec/paginate_spec.lua`** (10 pure-Lua specs) for `paginate` and
  `paginate_thread` (subtree-keeping, root counting, empty/over-range pages),
  plus HTTP integration tests that page a 27-root thread and a 27-post profile.
  Removed a redundant inline `paginate` unit test from the integration spec.

### Sorting
- **Real "controversial" ranking** — `sort.lua` now scores posts with Reddit's
  formula `(up + down) ^ (min(up, down) / max(up, down))` (`controversy_score`)
  instead of the old crude `|up - down|` distance. The exponent rewards an even
  up/down split while the base rewards volume, so a contested 500/500 post beats
  a quiet 1/1, and one-sided or unvoted posts score 0 (not controversial).
- **`Sort:sort` dispatch table** — the `if/elseif` algo chain is replaced by a
  `comparators` lookup keyed by algo name (unknown algos fall back to `hot`).
  Dropped the `print("Sorting by ...")` debug line and the dead commented-out
  code around it.
- **New `spec/sort_spec.lua`** (7 specs) — pure-Lua coverage for the comparators
  (controversial ordering + the zero-score guard, `top`/`best`, the unknown-algo
  fallback, and that the input table isn't mutated). It requires only
  `src.utils.sort`, so it runs without the lapis/DB stack.

### Breaking schema / data integrity
- **`PRAGMA foreign_keys = ON`** at runtime (and in tests) — the declared FKs
  are now enforced (verified: a vote on a non-existent post is rejected). The
  seed/runtime inserts were already FK-clean, so nothing broke.
- **Moderators join table** (migration `[11]`) replaces the `forum.moderator_ids`
  CSV: `Forum:can_moderate` checks the creator + the `moderators` table,
  `Forum:add_moderator` is idempotent, and creating a subreddit records its
  creator as a moderator. (`forum.moderator_ids` is now legacy/unused.)
- **`modlog` columns fixed** to integers with real FKs (were text); dropped the
  redundant `modlog.user_id`.

### Removed (dead code)
- **All `CREATE VIEW` machinery** — the per-subreddit `v_hot_*` views and the
  frontpage `v_hot_frontpage` view (migration `[13]`) plus `v_forum`
  (migration `[4]`) were unused (listings go through `Posts:get_listing`). The
  one remaining consumer, the `/domain/:domain` action, now uses a
  `get_listing({ domain = ... })` filter (a new LIKE filter on the canonical
  query) — which also fixes it to include self-posts and zero-vote posts the
  hot view omitted. With the views gone, `Forum:get_frontpage`, the unused
  `Forum.object_types` enum, and the legacy `forum.moderator_ids` column went
  too.
- **Dead files** `src/models/subreddit.lua` (a fully commented-out placeholder)
  and `src/utils/errors.lua` (API error helpers never wired up; `api.lua`
  doesn't require it).
- **Dead methods** `Users:get_name_from_id` / `Users:get_id_from_name` (zero
  callers).

### Security / validation
- **Reserved usernames enforced** — the `reserved_usernames` table is now
  seeded (migration `[2]`: `admin`, `root`, `mod`, `pagesix`, …) and the
  `Users.user_name` constraint rejects any of them at registration
  ("Username is reserved"). The table existed but was never checked.

### Quality / CI
- **Test suite now at 104 specs** (model/SQL + full HTTP integration), all green,
  with luacov coverage and a clean luacheck (0/0).
- **luacheck** added to the rockspec, Docker image, and CI (a `luacheck app`
  step gates the build), configured via `.luacheckrc` (luajit + `ngx` global;
  busted std for specs). Fixed all findings — **0 warnings / 0 errors** across
  64 files (removed dead `require`s and unused locals).
- CI now runs, per push: super-linter, **luacheck**, the **busted** suite with
  **luacov coverage**, and a Docker **build + `lapis migrate`** smoke test.

### Performance (SQLite)
- **Partial index** `posts(sub_id, created_at) WHERE deleted = 0 AND locked = 0`
  (migration `[6]`) — `Posts:get_listing` always filters out deleted/locked
  posts, so this is a precise (and smaller) match for the listing hot path.
  **Composite index** `comments(post_id, parent_comment_id)` (migration `[5]`)
  for the thread CTE's anchor row lookup.
- **Views evaluated + removed** — no SQL `VIEW`s are used: the main listing is
  dynamic (sort / time window / hidden / saved vary per request) so a view
  can't capture it, and the FK + partial indexes serve the hot path. The dead
  `v_hot_*` / `v_forum` views (migrations `[4]`/`[13]`) were dropped (see
  *Removed*). **sqlean** modules were evaluated one-by-one in `TODO.md`
  (`regexp`/`fuzzy`/`crypto` are the useful ones) — all deferred to a future
  infra task since they need `load_extension` + bundled `.so`s.
- **Covering indexes** `votes(post_id, comment_id, upvote)` and
  `votes(comment_id, upvote)` make the per-row vote-count subqueries index-only
  (verified `USING COVERING INDEX`).
- **`ANALYZE`** after the seed migrations (migration `[99]`) so the planner has
  table stats.
- Runtime **`busy_timeout=5000`** (avoids SQLITE_BUSY under WAL with multiple
  workers) + **`cache_size=-16000`** (~16 MB) set once per worker in the
  `before_filter` (Lapis's sqlite backend exposes no connect hook).

### Changed
- Enabled the **`/r/all`** and **`/r/popular`** meta-listing routes (the actions
  were already implemented and tested but commented out in `app.lua`).
- Pinned **Lapis >= 1.18.0** (we already run the latest; 1.16→1.18 brings a
  faster `url_for`, `db.clause + db.clause` OR-combining, `Model:update` with a
  `where` clause, and `simulate_request`/`simulate_action` test helpers). The
  integration suite now calls **`simulate_request`** directly (`mock_request` is
  a deprecated alias as of 1.18).
- **API deferred**: `src/api.lua` (~150 stub endpoints) is explicitly punted to
  a later phase — we're locking in the web browsing experience first.

### Security / auth hardening (issue #6)
- **Password hashing** — `src/utils/password` uses **bcrypt** (salted, slow).
  Registration hashes; login verifies; `verify` rejects non-bcrypt/legacy
  values rather than erroring. (Replaced an incomplete resty-sha512 sketch.)
- **CSRF** on the login and register forms (Lapis `csrf` token + per-session
  cookie); a tokenless POST is rejected and the form re-renders with an error.
- **Uncached auth routes** — removed `cached()` from login/register/password
  (they embed per-session CSRF tokens and must not be shared).
- **Error feedback** — login/register re-render with a message on bad
  credentials / mismatch / taken username / weak password (was a silent
  bare `return`).
- **Dev secret** now comes from `$SESSION_SECRET` (was a hardcoded `"hunter42"`).

### Added
- **RSS output feeds** — `GET /.rss` (frontpage) and `GET /r/:subreddit/.rss`
  emit valid, XML-escaped RSS 2.0 (`src/utils/rss`), served as
  `application/rss+xml`; a visible RSS link on the subreddit page. (RSS *import*
  of external feeds already exists in the seed migrations via `forum.feeds`.)
- **Reply notifications** — `notifications` table (migration `[9]`); commenting
  notifies the parent comment's author (reply) or the post's author (top-level),
  never yourself. `/inbox` lists them and marks them read; the header shows an
  unread count. (No direct messages — out of scope by request.)
- **Moderation (basic)** — `Forum:can_moderate` (creator or a listed
  `moderator_id`); `POST /post/:id/remove` lets a mod toggle removal (sets
  `locked`, which excludes the post from listings) and records it in `modlog`.
  The post page shows a remove/approve control to mods and `[removed]` markers.
- **Saved / hidden posts** — `saved_posts`/`hidden_posts` tables (migration
  `[8]`) with toggle models; `POST /post/:id/save` and `/hide`; a `/saved` page;
  hidden posts are filtered out of a user's listings (`get_listing`
  `exclude_hidden_for`/`saved_for`).
- **`rising` sort + time windows** — `rising` ranks by vote velocity (net score
  per hour); listings accept `?t=hour|day|week|month|year` (`src/utils/
  timewindow` + a `since` filter on `get_listing`) to scope e.g. `top?t=week`.
- **Pagination** — the frontpage, `/r/:sub`, `/r/all`, and `/r/popular` paginate
  via `?page=` (`src/utils/paginate`), with a prev/next `page_nav` fragment.
- **User karma** — `Users:karma` sums the net votes (up − down) on a user's
  posts and comments in SQL; shown on the user profile.
- **Full-text search (SQLite FTS5)** — migration `[7]` adds a `posts_fts`
  virtual table over post title/body, kept in sync by AFTER INSERT/UPDATE/DELETE
  triggers. `GET /search?q=` (`Posts:search`) matches with a quoted phrase
  (injection-safe), ranks by relevance (`ORDER BY rank`), and excludes deleted
  posts; the header search box now points at it.
- **Edit / delete** own posts and comments (author-only). Edits set `edited`
  (shown as "(edited)"). Deletes are soft: deleted comments stay in the thread
  as `[deleted]` so replies aren't orphaned (the recursive CTE now keeps them);
  deleted posts (new `posts.deleted` column, migration `[6]`) drop out of
  listings and render as `[deleted]`. Added a shared `spec/schema_helper` so
  specs build the full schema in one call.
- **Self / text posts** — the submit form now takes a title plus *either* a URL
  (link post) or a Markdown body (self post); `is_self` is set accordingly,
  `posts.url` is nullable, a Lapis `title` constraint validates submissions, and
  the post page renders the self-text body as sanitized Markdown.
- **Subscribe / unsubscribe** — `POST /subscribe/:subreddit` toggles a
  subscription (`Subscriptions:toggle`); a `before_filter` loads the signed-in
  user and their subscribed forums into every view, so the layout header's "my
  subs" nav and the `/subscribed` page populate, and the subreddit page shows a
  Subscribe/Unsubscribe button reflecting current state.
- **Test infrastructure**
  - `luacov` coverage: added to the rockspec, the Docker image, and CI
    (`busted --coverage` + a printed summary), configured via `.luacov` to
    measure only `app/` code. Baseline is **76.7%** (725/945 lines).
  - HTTP-level **integration tests** (`integration_spec`) that drive the real
    app through `lapis.spec.request.simulate_request` — routing, actions,
    auth/session, redirects, and rendering for every feature (browse, vote,
    comment/reply, subreddit creation, profiles). 38 specs total.
- **Smaller polish**
  - Markdown rendering for comment bodies (and user-profile comments), via a
    `src/utils/markdown` helper that renders Markdown and **sanitizes** the
    result with `web_sanitize` (XSS-safe). Falls back to escaped text if the
    optional rocks are absent.
  - Subreddit creation: `POST /subreddit/create`, a composable
    `create_subreddit` form on `/subreddits`, and a fixed `Forum.name`
    constraint (reserved-name set + length, validated by Lapis).
  - User profile pages now actually render: `Posts:get_listing` gained a
    `{ user_id = ... }` filter and `Comments:by_user` provides the user's
    comments with the same enriched fields the fragments expect.
- **Comment threading + submission**
  - `Comments:thread(post_id)` builds the thread with a SQLite **recursive
    CTE** (depth-first order via a materialized `path`, a `depth` per row,
    deleted subtrees excluded in SQL).
  - `POST /post/:post_id/comment` with optional `parent_comment_id`; bodies
    validated by a Lapis model constraint. JS-free `<details>` reply forms.
- **Voting** on posts (`POST /vote/post/:id/:dir`) and comments
  (`POST /vote/comment/:id/:dir`) via `Votes:cast` (create / toggle-off /
  switch); scores come from the listing/thread vote aggregates.
- **Performance**: indexes on the foreign keys the listing/thread/vote-count
  queries filter and join on (`posts.sub_id/user_id/created_at`,
  `comments.post_id/parent_comment_id/user_id`,
  `votes.post_id/comment_id/user_id`, `subscriptions.subreddit_id`).
- **Tests**: a Busted suite (23 specs) covering relations, listings, the
  threading CTE, voting, seed migrations, markdown, constraints, and index
  usage (`EXPLAIN QUERY PLAN`), runnable against in-memory SQLite.

### Fixed
- **Boot**: the container could not start. Fixed `init_by_lua` (`require
  "sqlite2"` — a module that does not exist), forwarded the LuaRocks paths
  into OpenResty in `config.lua`, installed deps into a world-readable tree at
  build time (`Dockerfile`), and ran workers as root so SQLite/WAL is
  writable. The image now boots via its entrypoint and serves with no manual
  steps.
- **Routing**: `/subreddits/search` and `/subreddits(/:type)` shared the route
  name `subreddits`, so the second silently replaced the first; bare
  `/subreddits` also lost to the `/(:sort)` homepage catch-all. Split into
  distinct, exact routes.
- **Listings**: replaced the dependency on pre-seeded `v_hot_*` views with
  `Posts:get_listing` (direct vote/comment aggregates, all sorts, zero-vote
  posts included); made `Sort` null-safe; fixed `r_subreddit`/`r_random` to
  use real `forum` rows instead of the hardcoded `object_types` enum;
  implemented the `r_popular` stub; listed all subreddits (not just subscribed)
  on `/subreddits`.
- **Templates**: numerous `for x in pairs(rows)` loops bound the index instead
  of the row (comments, subreddits, header) — switched to `ipairs`. Fixed the
  `subreddit_listing` fragment to read its passed locals, and a `self.subs`
  vs header `subs` variable collision.
- **Model relations / schema**: `comments.user` (`has_one`→`belongs_to`),
  `subscriptions.subreddit` (`Subreddits`→`Forum`), `posts.subreddit`
  (`key = sub_id`), `Posts:url_params` (real permalink); subscriptions FK →
  `forum(id)`, `posts.user_id` text→integer, unquoted malformed FK targets,
  `deafault`→`default`.
- **Actions**: `submit` (real post create from the session user + subreddit),
  `user` (404 on unknown), `comment` (removed calls to non-existent methods).
- **Seed migrations**: counter-as-id and `pairs`-index bugs in `[14]/[15]/
  [20]/[30]/[40]`; vote de-duplication; RSS fetch wrapped in `pcall` so a bad
  feed can't abort `lapis migrate`.

See `TODO.md` for what's next, the feature gaps, and performance/coverage
notes.

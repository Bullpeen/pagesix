# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

This run took the PoC from a rough, non-booting prototype to a running,
test-covered Reddit clone. Highlights, newest first:

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
    app through `lapis.spec.request.mock_request` — routing, actions,
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

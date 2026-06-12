# TODO / Roadmap

Status of the Page Six PoC and what's next. See `CHANGELOG.md` for history.

## Working now
Browse (frontpage + per-subreddit, sorts hot/new/top/controversial/best),
open a post, vote on posts and comments, post threaded comments/replies,
create subreddits, view user profiles, Markdown comment bodies. The Docker
image boots and serves; 23-spec Busted suite passes.

## Next up
- [ ] **Auth/password hardening** (GitHub issue #6 — the deferred capstone):
      hash passwords (bcrypt is a dep), CSRF tokens on forms, stop `cached()`
      on the login/register routes, real login error feedback.
- [ ] **Subscribe / unsubscribe** — the buttons are inert; wire
      `Subscriptions` + populate the header's "my subs" for the logged-in user.
- [ ] **Pagination** — every listing/thread is unbounded (`TODO paginate`
      markers throughout). Use Lapis `paginated`/SQLite `LIMIT/OFFSET` or
      keyset pagination.
- [ ] **Edit / delete** own posts & comments — the `edited`/`deleted` columns
      exist and `thread` already hides deleted; just need routes + UI.
- [ ] **Submit self-posts** with a body + Markdown preview (link vs text).

## Missing Reddit / HN features (backlog)
- Search (the search box has no backend) — good fit for **SQLite FTS5**.
- Time-windowed `top` (`?t=day|week|year`) and a `rising` sort (commented out).
- Saved / hidden posts; user karma (aggregate of vote scores).
- Moderation: the `modlog` table is unused — lock/sticky/remove, mod tools.
- Inbox / reply notifications; per-user message threads.
- Flair, awards/gold (currently static placeholders).
- Per-subreddit RSS in/out (seed does a one-shot import; no live feeds).
- Spam/quality filtering — `lapis-bayes` is a dependency but unused.
- Crossposts, image/video posts, post previews/thumbnails.
- Public API — `src/api.lua` is ~150 stub endpoints, disabled in `app.lua`.
- robots.txt / sitemap / output RSS feeds.

## SQLite performance notes
- [x] Indexes on the FK/sort columns the hot queries use (migration `[5]`);
      verified with `EXPLAIN QUERY PLAN` (the vote-count subquery now does
      `SEARCH ... USING INDEX votes_post_id_idx`).
- [x] WAL + `mmap_size` + `temp_store=MEMORY` already set (migration `[1]`).
- [ ] **Covering indexes** for the count subqueries, e.g.
      `votes(post_id, comment_id, upvote)` and `votes(comment_id, upvote)`, to
      make them index-only.
- [ ] **FTS5** virtual table for searching posts/comments by text.
- [ ] `ANALYZE` / `PRAGMA optimize` after migrations (migration `[99]` is a
      placeholder) so the planner has stats.
- [ ] Generated column for `posts.domain` (there's a commented-out
      `GENERATED ALWAYS AS (url_host(url))`) instead of computing it in Lua.
- [ ] `PRAGMA foreign_keys = ON` — FKs are currently declared but **not
      enforced** (some are even malformed-but-inert). Enabling means auditing
      insert order and the seed data.
- [ ] `PRAGMA busy_timeout` for write contention under WAL.

## Test coverage assessment
- **Strong**: data layer. 23 specs cover model relations, the listing/thread
  SQL (incl. the recursive CTE), vote casting/aggregation, every seed
  migration (FK integrity), Markdown rendering/sanitizing, model constraints,
  and index usage — all against in-memory SQLite via `lapis.spec`.
- **Gap**: no automated **action / HTTP-level** tests. The request cycle,
  routing, auth/session, and redirects were verified manually (Docker + curl)
  but aren't in CI — and several bugs this run were integration/template bugs
  (route-name collision, `pairs` loops, `self.subs` collision) that the
  model-level specs could not catch.
  - [ ] Add `lapis.spec.request.mock_request` specs for the key routes
        (home, `/r/:sub`, post page, vote, comment, create subreddit). Note:
        `app.lua`'s `before_filter` uses the nginx `after_dispatch` context, so
        the harness may need that guarded under the test env.
- **Gap**: no template/view rendering assertions; `.busted` had `coverage`
  enabled but `luacov` isn't installed — either install it or drop the flag.

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
- [x] **Subscribe / unsubscribe** — toggle action + the header's "my subs" and
      the `/subscribed` page now populate for the logged-in user.
- [x] **Pagination** — frontpage / `/r/:sub` / `/r/all` / `/r/popular` paginate
      via `?page=`; prev/next nav. (Comment threads still unbounded.)
- [x] **Edit / delete** own posts & comments — author-only edit (sets
      `edited`) and soft-delete. Deleted comments stay in the thread as
      `[deleted]` (replies kept); deleted posts drop from listings and show
      `[deleted]` on their page.
- [x] **Submit self-posts** — the submit form takes a title + (url OR Markdown
      body); self posts render their body on the post page. (Preview still TODO.)

## Missing Reddit / HN features (backlog)
- [x] Search — **SQLite FTS5** virtual table over post title/body, kept in sync
      by triggers; `GET /search?q=` ranks by relevance and excludes deleted.
- [x] Time-windowed listings (`?t=hour|day|week|month|year`) and a `rising`
      sort (vote velocity).
- [x] User karma (net votes on a user's posts + comments), shown on the profile.
- [x] Saved / hidden posts — per-user toggle; `/saved` page; hidden posts are
      excluded from a user's listings.
- [x] Moderation (basic): subreddit creator/mods can remove a post (recorded
      in `modlog`); removed posts drop from listings and show `[removed]`.
      Sticky / lock-comments / a public modlog page still TODO.
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

## Test coverage
- **38 specs**, ~76.7% line coverage (luacov; run `busted --coverage && luacov`).
- [x] Model/SQL layer: relations, listing/thread CTE, votes, seed migrations,
      markdown, constraints, index usage.
- [x] **HTTP integration** (`integration_spec` via `mock_request`): routing,
      actions, auth/session, redirects, rendering for every feature.
- [x] **luacov** wired into rockspec, Docker image, and CI.
- Remaining low-coverage modules are the not-yet-wired legacy actions
  (`register` 21%, `submit` 28%, `subscribed` 28%, `domain`/`r_random` ~30%,
  `comment` 36%) and `sort` 50% — these get covered as the features below land.

# TODO / Roadmap

Status of the Page Six PoC and what's next. See `CHANGELOG.md` for history.

## Working now
Browse (frontpage + per-subreddit, sorts hot/new/top/controversial/best),
open a post, vote on posts and comments, post threaded comments/replies,
create subreddits, view user profiles, Markdown comment bodies. The Docker
image boots and serves; 23-spec Busted suite passes.

## Next up
- [x] **Auth/password hardening** (issue #6): bcrypt password hashing
      (`src/utils/password`), CSRF on the login/register forms, uncached auth
      routes, login/register error feedback, dev secret from `$SESSION_SECRET`.
      Follow-ups: extend CSRF to all state-changing forms; password reset;
      re-hash/seed the demo users (their seeded passwords are plaintext and
      can't log in).
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
- [x] Reply notifications — replying to a post/comment notifies its author
      (not self); `/inbox` lists them + marks read; header shows an unread count.
      (Direct messages between users intentionally out of scope.)
- Flair, awards/gold (currently static placeholders).
- [x] RSS **out**: `/.rss` and `/r/:sub/.rss` output feeds. RSS **in** (live
      import of `forum.feeds`) still only runs as a one-shot seed migration.
- Spam/quality filtering — `lapis-bayes` is a dependency but unused.
- Crossposts, image/video posts, post previews/thumbnails.
- **API — deferred to a future phase.** `src/api.lua` is ~150 stub endpoints,
  disabled in `app.lua`. Intentionally on hold until the web browsing
  experience is locked in.
- robots.txt / sitemap / output RSS feeds.

## SQLite performance notes
- [x] Indexes on the FK/sort columns the hot queries use (migration `[5]`);
      verified with `EXPLAIN QUERY PLAN` (the vote-count subquery now does
      `SEARCH ... USING INDEX votes_post_id_idx`).
- [x] WAL + `mmap_size` + `temp_store=MEMORY` already set (migration `[1]`).
- [x] **Covering indexes** `votes(post_id, comment_id, upvote)` and
      `votes(comment_id, upvote)` so the count subqueries are index-only
      (verified with `EXPLAIN QUERY PLAN ... USING COVERING INDEX`).
- [x] **FTS5** virtual table for search.
- [x] `ANALYZE` after the seed migrations (migration `[99]`).
- [x] Runtime `PRAGMA busy_timeout=5000` + `cache_size=-16000` set once per
      worker (Lapis's sqlite backend has no connect hook).
- [ ] `PRAGMA foreign_keys = ON` — FKs are declared but **not enforced**;
      enabling needs an insert-order + seed-data audit (and the `modlog` text
      FK columns fixed).
- [ ] Generated column for `posts.domain` (`GENERATED ALWAYS AS
      (url_host(url))`) instead of computing it in Lua.
- [ ] **sqlean** extensions (load via `sqlite3.load_extension` once the `.so`s
      are bundled): `fuzzy` for typo-tolerant search ranking, `text`/`regexp`
      for domain/URL extraction + content normalization, `crypto` for secure
      tokens (password reset), `stats` for ranking. Needs `load_extension`
      enabled + per-platform builds in the image.

## Test & quality
- **75 specs** (model/SQL + full HTTP integration via `mock_request`), luacov
  coverage, and **luacheck** (0 warnings / 0 errors).
- CI per push: super-linter, **luacheck** (`luacheck app`), **busted +
  luacov**, and a Docker **build + `lapis migrate`** smoke test.
- [x] Model/SQL layer, HTTP integration for every feature, luacov + luacheck.
- [ ] Optional: **stylua** formatting check (one-time reformat) and a coverage
      threshold gate.

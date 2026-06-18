# TODO / Roadmap

Status of the Page Six PoC and what's next. See `CHANGELOG.md` for history.

## Working now
Browse (frontpage, `/r/:sub`, `/r/all`, `/r/popular`) with sorts
hot/new/top/controversial/best/rising and `?t=` time windows + pagination;
full-text search (FTS5); open a post; vote on posts & comments; submit
link/self posts; post threaded comments/replies with Markdown; edit/delete own
posts & comments; subscribe/unsubscribe; saved/hidden posts; user profiles +
karma; reply notifications (`/inbox`); RSS in/out feeds; bcrypt + CSRF auth.

Forum-generalization layer (all shipped): role-based moderation via a privilege
matrix (`owner`/`moderator`/`member` + site `admin`); an Admin Control Panel
(`/admin`); cached user reputation + trust levels; a new-user post-approval
queue (`/r/:sub/queue`) with rate limiting; tags (`/t/:tag`); `@mentions`;
accept-answer Q&A mode; and OAuth login. The Docker image boots and serves;
**219-spec Busted suite + luacheck pass**.

## Next up
- [x] **Auth/password hardening** (issue #6): bcrypt password hashing
      (`src/utils/password`), CSRF on the login/register forms, uncached auth
      routes, login/register error feedback, dev secret from `$SESSION_SECRET`.
      Follow-ups **(done)**: CSRF now covers *every* state-changing form via a
      global `before_filter` (403 on bad/missing token); **password reset**
      (`/password` issues a one-shot token → `/password/reset` sets a new bcrypt
      password; `password_resets` table, migration `[17]`); and the seeded demo
      users are **re-hashed** — seed migration `[14]` bcrypts at creation and
      idempotent migration `[50]` re-hashes any leftover plaintext (demo login is
      username + `hunter2`).
- [x] **Subscribe / unsubscribe** — toggle action + the header's "my subs" and
      the `/subscribed` page now populate for the logged-in user.
- [x] **Pagination** — frontpage / `/r/:sub` / `/r/all` / `/r/popular` paginate
      via `?page=`; prev/next nav. (Comment threads still unbounded.)
- [x] **Edit / delete** own posts & comments — author-only edit (sets
      `edited`) and soft-delete. Deleted comments stay in the thread as
      `[deleted]` (replies kept); deleted posts drop from listings and show
      `[deleted]` on their page.
- [x] **Submit self-posts** — the submit form takes a title + (url OR Markdown
      body); self posts render their body on the post page. A *Preview* button
      renders the Markdown without posting (and submit errors now show on-page).

## Forum generalization (community-forum / NodeBB direction)
Extending the link-aggregator into a community forum. Build order is
dependency-driven (foundations first); full plan in
`.context/forum-features-plan.md`.
- [x] **RBAC privilege matrix** — generalized the binary `Forum:can_moderate`
      into a named-privilege system (`utils/privileges.lua`):
      `Privileges.can(user, forum, privilege)` resolves a forum role
      (`owner` > `moderator` > `member`) against a matrix, and a global site
      `admin` overrides every check. New `roles` + `site_roles` tables (migration
      `[100]`, backfilled from creators + the `moderators` table) and
      `models/roles`/`models/site_roles`. The `lock`/`sticky`/`mod_remove`/
      `refresh_feeds` actions request their specific privilege;
      `Forum:can_moderate` stays as a back-compat shim. (`privileges_spec`.)
- [x] **Admin Control Panel** — `/admin` dashboard (counts), `/admin/users`
      (grant/revoke admin, self-lockout guard), `/admin/settings` (runtime
      key/value, `site_settings` table, migration `[101]`), gated by the site
      `admin` role (`utils/admin_guard`). First admin bootstraps from the
      `ADMIN_USERNAMES` config/env via `Privileges.ensure_admin`. (`admin_spec`.)
- [x] **User reputation** — cached `users.reputation` column (migration `[102]`,
      backfilled), refreshed by `Users:recompute_reputation` on every vote.
      `Users:trust_level` bands (new/member/trusted/veteran) drive a profile
      badge and gate new-user behaviour for the post queue. (`reputation_spec`.)
- [x] **Post queue + new-user rate limit** — `approved` flag on posts/comments
      (migration `[103]`); brand-new users held (`utils/queue`), filtered from
      listings/search/threads/profiles. Moderator queue at `/r/:sub/queue`
      (approve/reject → modlog), dashboard pending counts, and `utils/ratelimit`
      flood control on submit/comment. (`queue_spec`.)
- [x] **Tags** — `tags` + `post_tags` tables (migration `[104]`), `models/tags`
      (`normalize`/`set_for_post`/`for_post`, ≤5 slugs/post). Tags input on submit
      + edit, chips on the post page, `/t/:tag` listing via a `get_listing` tag
      filter. (`tags_spec`.)
- [x] **@mentions** — `utils/mentions` (extract/resolve/linkify, skips
      emails+code); `mention` notifications for comments and post bodies via the
      `[105]` notifications rebuild (nullable `comment_id` + new `post_id`);
      linkified in Markdown; inbox renders them. (`mentions_spec`.)
- [x] **Accept-answer mode** — `posts.is_question` + `accepted_comment_id`
      (migration `[106]`); `POST /comment/:id/accept` toggles, gated to the OP or
      the `accept_answer` privilege. Accepted-answer badge/highlight in-thread,
      question/solved badges in listings + post page. (`accept_spec`.)
- [x] **OAuth login** — `oauth_identities` table (migration `[107]`),
      authorization-code flow (`utils/oauth`, `/auth/:provider` + `/callback`),
      link-or-create with an unusable password, GitHub/Google config presets, and
      provider buttons on login/register. (`oauth_spec`.)

## Missing Reddit / HN features (backlog)
- [x] Search — **SQLite FTS5** virtual table over post title/body, kept in sync
      by triggers; `GET /search?q=` ranks by relevance and excludes deleted.
- [x] Time-windowed listings (`?t=hour|day|week|month|year`) and a `rising`
      sort (vote velocity).
- [x] User karma (net votes on a user's posts + comments), shown on the profile.
- [x] Saved / hidden posts — per-user toggle; `/saved` page; hidden posts are
      excluded from a user's listings.
- [x] Moderation: subreddit creator/mods can remove a post (recorded in
      `modlog`); removed posts drop from listings and show `[removed]`. **Sticky**
      (pins to the top of the subreddit listing), **lock-comments** (thread stays
      visible but rejects new comments/replies), and a **public modlog page**
      (`/r/:sub/modlog`) are now done — sticky/comments_locked are separate
      `posts` columns (migration `[18]`), each toggle is mod-only + CSRF-guarded
      and recorded in the modlog.
- [x] Reply notifications — replying to a post/comment notifies its author
      (not self); `/inbox` lists them + marks read; header shows an unread count.
      (Direct messages between users intentionally out of scope.)
- Flair, awards/gold (currently static placeholders).
- [x] **Front-end clean slate** — dropped the 14k-line vendored `saidit.css` and
      the ~75k-line dead `static/js` tree for a single **classless** `app.css`
      (no class/id selectors — styles semantic elements + `data-*` only) and
      self-hosted **Datastar** (no hand-written JS). Templates carry no `class`
      and no `id` except the Datastar score-patch span. Menus + inline reply/edit
      toggles are `data-signals`/`data-show`; voting is progressive (form POST
      fallback + Datastar `@post` → SSE score patch via `utils/datastar`). Vote
      control extracted to `utils/widgets`.
- [x] RSS **out**: `/.rss` and `/r/:sub/.rss` output feeds. RSS **in**: a live
      importer (`utils/feed_import` + `utils/feed_parse`, luaexpat-based, no
      `feedparser` dep) fetches each feed, parses RSS/Atom, and creates posts for
      new entries deduped on `posts.external_guid`. Feeds live in their own
      `feeds` table (migration `[19]`, seeded from the legacy `forum.feeds` CSV in
      `[60]`); imported posts are attributed to an `rss_bot` system user. Mods
      trigger a refresh via `POST /r/:sub/feeds/refresh` (CSRF). The in-process
      `ngx.timer.every` **scheduler** (`utils/feed_scheduler`) now refreshes due
      feeds automatically: non-blocking `lua-resty-http` fetches inside the
      timer, a cross-worker shared-dict lock (`feed_scheduler`) so only one
      worker refreshes per tick, ETag/Last-Modified **conditional GET** (cached
      in `feeds.etag`/`last_modified`, migration `[21]`, 304 ⇒ unchanged), and
      exponential backoff on consecutive failures (`Feeds:due`). Enabled per
      environment via the `feed_scheduler` config block. A mod-only **feed
      management UI** (`/r/:sub/feeds`) lists each feed with its fetch state and
      can add / remove / enable-disable feeds (CSRF-guarded, logged to the
      modlog); the seed CSV is now just the initial population.
- [x] Spam/quality filtering — `lapis-bayes` is now wired up (`utils/spam`):
      pure-Lua tokenizer, built-in corpus trained in migration `[12]`, and a
      fail-open `is_spam` check on post + comment submission. (lapis-bayes is
      Postgres-shaped; we supply our own tokenizer + SQLite tables.)
- [x] Crossposts + image posts + thumbnails — `utils/media` detects image links
      (-> `posts.thumbnail`, rendered on listings + post page); `POST
      /post/:id/crosspost` re-shares into another sub via
      `posts.crosspost_parent_id` with source attribution. (Video embeds still
      out of scope.)
- **API — deferred to a future phase.** `src/api.lua` is ~150 stub endpoints,
  disabled in `app.lua`. Intentionally on hold until the web browsing
  experience is locked in.
- [x] **robots.txt / sitemap / well-known** — app-served `/robots.txt`,
      `/sitemap.xml` (subreddits + recent posts), and `/.well-known/security.txt`
      (RFC 9116). Output RSS feeds already done above.

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
- [x] `PRAGMA foreign_keys = ON` enforced at runtime + in tests; `modlog`
      columns fixed to integer FKs; moderators moved to a join table; the
      legacy `forum.moderator_ids` CSV column has been **dropped**.
- [x] **Partial index** `posts(sub_id, created_at) WHERE deleted = 0 AND
      locked = 0` (migration `[6]`) — a tight match for the `get_listing`
      hot path (which always filters out deleted/locked) and smaller than a
      full index. **Composite index** `comments(post_id, parent_comment_id)`
      (migration `[5]`) for the thread CTE anchor
      (`WHERE post_id = ? AND parent_comment_id IS NULL`).
- [x] **Views**: we use no SQL `VIEW`s — the main listing is dynamic
      (sort/time/hidden/saved vary per request), so a view can't capture it,
      and the FK/partial indexes above already serve the hot path. The dead
      `v_hot_*` / `v_forum` views have now been **removed** (see code-comments
      section).
- [x] **Stored `posts.domain`** — a normalized link host is now a real column
      (migration `[108]`), populated once at write time by `Posts:create` (via
      `utils/url`'s socket.url parser) and backfilled for existing rows. The
      `GENERATED ALWAYS AS (...)` form was **evaluated and declined**: socket.url
      parses hosts more correctly than any SQL regex, and an extension-backed
      generated column faults every INSERT (STORED) or SELECT (VIRTUAL) on a
      connection without the sqlean `.so` loaded — i.e. the test suite and
      `lapis migrate`. The stored column also fixes the `/domain/:host` filter,
      which was a substring `url LIKE '%host%'` that conflated `notexample.com`
      and `?ref=host`; it is now an exact, indexed match.
- [x] **sqlean** extensions — the bundle (`/usr/local/lib/sqlite/sqlean.so`,
      pinned `0.28.3` in the Dockerfile) is loaded into Lapis's live connection
      per worker by `src/utils/sqlite_ext.lua`; see **`docs/sqlean-plan.md`** for
      the final per-module decisions. Confirmed against the actual `.so` that the
      bundle exposes both the unprefixed aliases (`jaro_winkler`, `dlevenshtein`,
      `regexp_replace`, …) and the `fuzzy_*` names. Per-module verdict:
  - `fuzzy` — **adopted**: `jaro_winkler` powers typo-tolerant **subreddit
    search** (`Forum:search`) and a word-level **post-search fallback**
    (`Posts:search` → `fuzzy_title_search`, used only when FTS5 finds nothing).
  - `regexp` — **adopted (light)**: `regexp_replace` normalizes punctuation when
    splitting titles into words for the fuzzy post-search fallback. Not used for
    `posts.domain` — socket.url parses hosts more correctly (see above).
  - `crypto` — **not needed**: secure tokens use `openssl.rand` (migration `[17]`
    / `models/password_resets`); `hex(randomblob())` covers the rest.
  - `text` — **not adopted**: `text_substring`/`split` are doable in Lua.
  - `stats` / `math` — **not adopted**: `hot`/`rising` math stays in `sort.lua`;
    revisit if SQL-side ranking becomes a bottleneck.
  - `uuid` — **deferred to the API phase**: stable external ids.
  - `define` — **not adopted**: no reusable SQL function needed once the
    `url_host` generated column was dropped.
  - `ipaddr`, `vsv`, `unicode`, `time`, `besttype` — **not needed** for this
    workload.

## From code comments (TODO/FIXME in the source)
- [x] **Link flair** — replaced the dead `<% -- TODO ...linkflairlabel... %>`
      placeholder in `fragments/posts.etlua` with a real feature: posts carry an
      optional author-set `link_flair` label (nullable column on `posts`). Submit
      trims/blank-drops it and caps it at 64 chars (`actions/submit.lua`, with a
      `flair` field in `fragments/form_submit.etlua`); `get_listing`/`search`
      select it; the listing and post-page (`fragments/post.etlua`) render a
      `linkflairlabel` span (existing reddit CSS styles it). Covered by model +
      HTTP integration specs.
- [x] **Real "controversial" ranking** — replaced the crude `|up - down|`
      distance with the Reddit formula `(up + down) ^ (min/max)`
      (`controversy_score` in `sort.lua`); one-sided/unvoted posts score 0.
- [x] **Refactor `Sort:sort`** — the if/elseif chain is now a `comparators`
      dispatch table keyed by algo name (default `hot`); dropped the debug
      `print` and dead commented code (`sort.lua`).
- [x] **Removed the dead `v_hot_*` / `v_forum` views + `Forum:get_frontpage()`**
      — listings use `Posts:get_listing`; the last view consumer (`domain.lua`)
      was switched to a `get_listing({ domain = ... })` filter, so all the
      `CREATE VIEW` blocks (migrations `[4]`/`[13]`), `get_frontpage`, and the
      dead `Forum.object_types` enum are gone. Also deleted the unused
      `models/subreddit.lua` and `utils/errors.lua`, and the dead
      `Users:get_name_from_id`/`get_id_from_name` helpers.
- [x] **Enforce reserved usernames** at registration — `reserved_usernames`
      is now seeded (migration `[2]`) and the `Users.user_name` constraint
      rejects any name in it (returns "Username is reserved").
- [x] **Finish the single-comment permalink view** — `Comments:permalink_thread`
      returns the focused comment + its full reply subtree, optionally preceded
      by `?context=N` ancestor comments; `actions/comment.lua` renders it through
      the shared comments fragment (the dead static `fragments/comment.etlua`
      mockup is gone).
- [x] **Paginate comment threads and user profiles** — the post page paginates
      its comment thread by *root* comment (a new `utils/paginate_thread` keeps
      each root's whole subtree on one page), and the profile paginates its
      posts + comments off a shared `?page=`. Both reuse the `page_nav` fragment.
- [x] **Seed perf** — migration `[13]`'s inline `io.open`/`cjson.decode` is now
      `utils/read_json` (unit-tested; tolerates a missing file). The
      `misc.lua:84` `Users:select()` → `:count()` note was a non-fix (the rows
      are needed to pick a random user); comment corrected in place.
- [x] **Schema cleanup** (audited — nothing risky left to do):
  - *Text-typed `modlog` FK columns* → **done**: `modlog` is created with all
    integer FKs (`mod_id`/`sub_id`/`post_id`/`comment_id`) under
    `foreign_keys = ON` (migration `[4]`); the redundant `modlog.user_id` was
    dropped (it duplicated `mod_id`).
  - *Drop `modlog.sub_id`* → **declined, kept on purpose**: it's a deliberate
    denormalization for the append-only audit log (natural key for
    sub/comment-level actions; survives a post being hard-deleted). Annotated
    in `migrations.lua`.
  - *Rename `forum.creator_id`* → **declined**: clear name, no target/motivation,
    and a rename touches ~25 call sites (model `can_moderate`, create-sub
    action, seed, 6 spec files) for zero benefit. Removed the stale
    `-- TODO rename` marker.

## Test & quality
- **219 specs** (model/SQL + full HTTP integration via `simulate_request`), luacov
  coverage, and **luacheck** (0 warnings / 0 errors).
- CI per push: super-linter, **stylua** (`--check app`), **luacheck**
  (`luacheck app`), **busted + luacov** (with an 80% coverage gate), and a
  Docker **build + `lapis migrate`** smoke test.
- [x] Model/SQL layer, HTTP integration for every feature, luacov + luacheck.
- [x] **stylua** — one-time repo reformat (`.stylua.toml` tabs/100-col,
      `.styluaignore` for vendored/generated), with a `stylua --check app` CI
      job. **Coverage gate** — `.luacov` excludes the disabled `api.lua` stubs
      (active-code coverage ~89%); CI fails under an 80% threshold.

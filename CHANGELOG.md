# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

This run took the PoC from a rough, non-booting prototype to a running,
test-covered Reddit clone. Highlights, newest first:

### UI clean slate: new CSS + Datastar, drop the vendored Reddit front-end
- **New classless stylesheet** — replaced the 14k-line vendored `saidit.css`
  (plus `compact`/`highlight`/`mobile` and the `.less`/`.scss` soup) with a single
  `static/css/app.css`. It uses **no class or id selectors**: styling targets
  semantic elements and `data-*` attributes (Datastar's own idiom). Templates
  carry no `class` attributes and no `id`s except the score `<span>` Datastar
  patches after an async vote. Keeps the reddit/saidit silhouette (header, link
  listing + vote column, threaded comments, forms, badges, cards, dropdowns).
- **Datastar (self-hosted v1.0.2)** replaces htmx + the dead `base.js`. Used for
  all client interactivity with no hand-written JS: the header "my subs"/account
  dropdowns and the inline comment reply/edit and post-edit toggles are
  `data-signals` + `data-show`; voting is progressive — a plain `<form>` POST is
  the no-JS fallback, and Datastar intercepts the submit (`data-on:submit__prevent
  → @post`) so the vote action replies with an **SSE element patch** that updates
  just the score in place (no reload). New `utils/datastar` (request detection +
  `text/event-stream` patch helper) and `Votes:post_score`/`:comment_score`; the
  CSRF filter now also accepts an `X-Csrf-Token` header (Datastar posts JSON, not
  a form field).
- **Every template rewritten** classless — layout, header, sidebar, footer, nav,
  listing, post, comments, submit/register/login/password, subreddit(s), inbox,
  modlog, queue, feeds, tag, and the admin views — as clean semantic HTML with
  `data-*` hooks, dropping the dead Reddit markup (recaptcha, strength-meters,
  fake mockup rows, `onclick`) and the legacy form classes
  (`split-panel`/`input_row`/`c-form-*`/`primary_form`/…) plus the CSS shims that
  propped them up. Deleted six now-dead fragments (`link_listing`, `login_panel`,
  `menubar`, `commentsignupbar`, `subreddit_title`, `subreddit_moderators`,
  `error`). The vote control is a shared `utils/widgets` helper (etlua's
  parameterless `render` can't pass per-row values inside the posts/comments loops).
- **Deleted** the entire unreferenced `static/js` tree (~75k lines of vendored
  jQuery/React/Reddit JS) and all unused images — `static/` is now just
  `css/app.css`, `js/datastar.js`, and `favicon.ico`.
- Spec: the Datastar vote path returns an `text/event-stream` score patch when the
  `Datastar-Request` header is set (CSRF via `X-Csrf-Token`), vs the 302 redirect
  for a plain form post. (220 specs.) Verified visually (home + post page).

### Forum generalization: OAuth login
- **Sign in with an external provider** — `utils/oauth` implements the OAuth2
  authorization-code flow: `/auth/:provider` stashes an anti-CSRF `state` and
  redirects to the provider; `/auth/:provider/callback` validates the state,
  exchanges the code, and links-or-creates a local user. New `oauth_identities`
  table (migration `[107]`) keyed on `(provider, provider_user_id)`.
- **Accounts** — a first-time login creates a user with a derived (collision-
  disambiguated) username and an unusable password, mirroring the `rss_bot`
  system user; a returning identity signs into the same account. Provider buttons
  show on the login/register pages.
- **Configurable** — providers come from `config.oauth`; GitHub and Google ship
  as presets enabled via `*_CLIENT_ID`/`*_CLIENT_SECRET` env vars. The network
  step is a single seam (`OAuth.identify`) so it's stubbable.
- Specs: authorize-url building, link-or-create (new/repeat/colliding), and the
  start + callback actions including state validation. (219 specs.)

### Forum generalization: accept-answer mode
- **Q&A posts** — a post can be flagged a question (an "Ask a question" checkbox
  on submit; `posts.is_question`), and the OP or a moderator can mark one comment
  as the accepted answer (`posts.accepted_comment_id`, migration `[106]`).
- **Accept toggle** — `POST /comment/:id/accept` (author or the `accept_answer`
  RBAC privilege) sets/clears the accepted comment. The accepted comment gets a
  badge + highlight in the thread and an accept/unaccept control for OP/mods;
  questions show a `question`/`solved` badge on the post page and in listings
  (`is_question`/`accepted_comment_id` added to `get_listing`).
- Specs: the question flag, the accept/unaccept toggle, authorization (OP, mod,
  and a denied stranger), and the listing fields. (210 specs.)

### Forum generalization: @mentions
- **Mention users** — `utils/mentions` extracts `@username` tokens (frontier
  pattern so emails like `bob@x` and code spans/fences are skipped), resolves
  them to existing users, and linkifies them to profile links during Markdown
  rendering.
- **Notifications generalized** — migration `[105]` rebuilds the `notifications`
  table so a row can reference a comment OR a post body (`comment_id` made
  nullable, new nullable `post_id`); `for_user` LEFT JOINs both. Commenting and
  submitting a self post now fire `mention` notifications to mentioned users
  (skipping yourself and a reply recipient who'd otherwise be notified twice;
  held content notifies no one until approved). The inbox renders mention rows.
- Specs: extraction/linkify edge cases, resolution, comment + post-body mention
  notifications, the no-double-notify rule, and the `[105]` rebuild. (205 specs.)

### Forum generalization: tags
- **Tag posts** — a flat tag vocabulary (`tags`) and a post<->tag join
  (`post_tags`), migration `[104]`, with `models/tags` + `models/post_tags`.
  `Tags.normalize` parses a free-text field ("Lua, Web") into deduped lowercase
  slugs, capped at 5/post; `Tags:set_for_post` find-or-creates and replaces a
  post's tags; `Tags:for_post` reads them back.
- **Surfaced** — a tags input on the submit form (and re-tagging via post edit),
  tag chips on the post page, and a `/t/:tag` listing (a new `tag` filter on
  `Posts:get_listing`, normalized so `/t/Roadmap` finds `roadmap`).
- Specs: normalization (split/slug/dedupe/cap), set/replace + tag reuse, the
  listing filter, and the submit → `/t/:tag` round trip. (198 specs.)

### Forum generalization: post/comment approval queue + rate limiting
- **Hold new users' content** — posts and comments gain an `approved` flag
  (migration `[103]`, default 1 so existing content stays visible). Brand-new
  users (trust level `new`) have their submissions held (`approved = 0`);
  moderators/owners/admins and reputable users post directly
  (`utils/queue.should_hold`). Held content is filtered out of listings, search,
  threads, and profiles, and a held post's own page is visible only to its author
  and the sub's moderators.
- **Moderator queue** — `/r/:subreddit/queue` (gated by the RBAC `approve`
  privilege) lists pending posts + comments with approve/reject buttons; approve
  publishes, reject approves-and-soft-deletes, both recorded in the modlog. A
  "queue" link appears in the subreddit header for mods, and the admin dashboard
  shows site-wide pending counts.
- **Flood control** — `utils/ratelimit` caps posts (10) and comments (30) per
  user per 10-minute window in the submit/comment actions.
- Specs: holding policy (new vs established vs mod), rate-limit threshold,
  listing/thread visibility filtering, the held-post page guard, submit-action
  holding, and the queue review flow (access control + approve/reject + modlog).
  (191 specs.)

### Forum generalization: user reputation + trust levels
- **Persisted reputation** — a cached `users.reputation` column (migration `[102]`,
  backfilled from existing votes) stores what `Users:karma()` computes live;
  `Users:recompute_reputation` refreshes it and the vote action calls it for the
  content author on every up/down vote.
- **Trust levels** — `Users:trust_level(reputation)` maps a score to
  `new` < `member` (10) < `trusted` (100) < `veteran` (250); the user profile now
  shows the reputation total and a trust badge. The threshold helper is the hook
  the upcoming post queue uses to spot new users.
- Specs: trust-level boundaries, recompute matches karma + persists, downvotes
  lower it, the `[102]` backfill, and the vote-action wiring through a real
  request. (181 specs.)

### Forum generalization: Admin Control Panel
- **Authed `/admin` panel** replaces the `"Go away"` stub, gated by the site
  `admin` role (`utils/admin_guard` → 302 to login for anon, 403 for non-admins).
  Routes live in `src/admin.lua`: `/admin` (dashboard with user/forum/post/
  comment/admin counts), `/admin/users` (list users with karma + admin flag;
  grant/revoke the admin role — self-revoke blocked to avoid lockout), and
  `/admin/settings` (a runtime key/value editor backed by a new `site_settings`
  table, migration `[101]`, model `models/site_settings`).
- **Admin bootstrap** — `Privileges.ensure_admin(user)` grants the role on first
  visit to any username listed in the `admin_usernames` config (from the
  `ADMIN_USERNAMES` env var), so a fresh install has a way in; thereafter admins
  manage each other from `/admin/users`.
- The header shows an **admin** link for site admins (`self.is_admin` set in the
  app before-filter).
- Specs: anon/non-admin/admin access, grant/revoke + self-lockout guard,
  non-admin POSTs ignored, settings upsert + default fallback, and the config
  bootstrap path. (176 specs.)

### Forum generalization: RBAC privilege matrix
First step of generalizing the link-aggregator into a community forum (full
roadmap in `.context/forum-features-plan.md`).
- **Named privileges replace binary mod checks** — generalized the single
  `Forum:can_moderate` chokepoint into a privilege matrix (`utils/privileges.lua`).
  `Privileges.can(user_id, forum, privilege)` resolves a user's forum role
  (`owner` > `moderator` > `member`) and looks up the privilege; a global site
  `admin` overrides every forum-level check. Owners hold all privileges;
  moderators hold the day-to-day content powers (`remove`, `lock`, `sticky`,
  `approve`, `manage_feeds`, `accept_answer`) but not the owner-only governance
  powers (`manage_mods`, `edit_forum`, `ban`).
- **Roles tables** — new `roles` table (per-forum role per user) and `site_roles`
  table (global admin), created and backfilled by migration `[100]` from existing
  forum creators (→ `owner`) and `moderators` rows (→ `moderator`). New models
  `models/roles` and `models/site_roles`; the legacy `moderators` table is left
  intact. `Forum:add_owner`/`add_moderator` now write role rows.
- **Action call sites** — `lock`, `sticky`, `mod_remove`, and `refresh_feeds` now
  request their specific privilege instead of a blanket mod check;
  `Forum:can_moderate` stays as a back-compat shim over the matrix (still used for
  the generic mod-tools UI flags). No behavior change for existing mods/creators.
- Specs: role resolution, the full matrix (owner/moderator/member), site-admin
  override, the `can_moderate` shim, `Roles:assign` idempotency, and the migration
  `[100]` backfill. (167 specs.)

### Live RSS/Atom import
- **On-demand feed import** — replaces the dead one-shot seed path (which needed
  the uninstalled `feedparser`). `utils/feed_parse` parses RSS 2.0 and Atom using
  luaexpat (`lxp.lom`) only — no network, fully unit-tested against fixtures;
  `utils/feed_import` fetches a feed (non-blocking `resty.http` under OpenResty,
  blocking luasocket/luasec otherwise; injectable for tests), parses it, and
  creates posts for entries not already imported.
- **Dedup** — imported posts carry the feed entry's guid/link in a new
  `posts.external_guid` column (migration `[19]`); re-running an import creates
  nothing new.
- **Feeds table** — feeds moved out of the `forum.feeds` CSV into a `feeds` table
  (`sub_id`, `url`, `enabled`, `last_fetched_at`, `last_status`, `failure_count`;
  migration `[19]`), seeded from the legacy CSV in `[60]`. Fetch outcomes are
  recorded so the scheduler can back off dead feeds.
- **Attribution + trigger** — imported posts belong to an on-demand `rss_bot`
  system user (unusable password). Moderators refresh a sub's feeds via
  `POST /r/:sub/feeds/refresh` (mod-only, CSRF), with a "refresh feeds" button on
  the subreddit header.
- **In-process scheduler** (`utils/feed_scheduler`) — an `ngx.timer.every` loop
  started in `init_worker_by_lua` refreshes due feeds automatically, so imports
  no longer wait on a manual trigger. A cross-worker lock in the `feed_scheduler`
  shared dict (`:add` with a TTL) means exactly one worker refreshes per tick;
  the timer uses the non-blocking `resty.http` client. Each pass refreshes only
  feeds that are **due** (`Feeds:due`): a healthy feed every `base_interval`
  seconds, a failing one backing off exponentially (`base * min(2^failures, 64)`).
  **Conditional GET** caches each response's ETag / Last-Modified
  (`feeds.etag` / `last_modified`, migration `[21]`) and replays them as
  If-None-Match / If-Modified-Since; a `304` counts as an unchanged success.
  Enabled per environment via the `feed_scheduler` config block.
- **Feed management UI** — a mod-only page at `/r/:sub/feeds` (linked from the
  subreddit header) lists every feed with its enabled/disabled state, last fetch
  time, last result, and failure count, and offers add / remove / enable-disable
  controls (`Feeds:list` / `add` / `remove` / `set_enabled`; routes
  `feeds/add`, `feeds/:id/remove`, `feeds/:id/toggle`). Each mutation is
  CSRF-guarded, scoped so a mod only touches their own sub's feeds, and recorded
  in the modlog. The legacy `forum.feeds` CSV is now just the initial seed.
- Specs: parser (RSS/Atom/malformed/long-title), import + dedup, fetch-failure
  bookkeeping, the mod-only endpoint (non-mods ignored), due/backoff selection,
  conditional-GET + 304 handling, `refresh_all`, the scheduler's lock/dispatch
  logic, and the feed-management page + add/toggle/remove (mod-gated). (159 specs.)

### Moderation: sticky, lock-comments, public modlog
- **Sticky posts** — mods can pin a post to the top of its subreddit listing
  (`POST /post/:id/sticky`, toggle). New `posts.stickied` column (migration
  `[18]`); `r_subreddit` pins stickied posts to the top after sorting, before
  pagination; a "stickied" badge shows on the listing and post page.
- **Lock comments** — mods can lock a thread (`POST /post/:id/lock`, toggle); a
  locked thread stays visible but `comment_create` rejects new comments/replies,
  the post page shows a locked notice instead of the comment box, and reply forms
  are hidden. New `posts.comments_locked` column — separate from `locked`, which
  the remove/approve flow already uses to hide a post, so locking doesn't drop
  the post from listings.
- **Public modlog** — `GET /r/:sub/modlog` lists a subreddit's moderator actions
  (remove/approve, sticky/unsticky, lock/unlock) newest-first with the acting mod
  and the affected post (`models/modlog:for_subreddit`); linked from the subreddit
  header. The sticky/lock toggles write modlog entries like remove already did.
- All three toggles are moderator-only (`Forum:can_moderate`) and CSRF-guarded.
  Specs cover sticky pin + badge, lock blocks/then-restores commenting, non-mod
  actions are ignored, and the modlog renders the recorded actions. (141 specs.)

### Auth follow-ups: site-wide CSRF, password reset, seed re-hash, submit preview
- **CSRF on every state-changing form** — promoted CSRF from just login/register
  to a single global `before_filter` (`app.lua`) that validates any non-GET
  request (403 on failure; the dev `/console` REPL is exempt) and exposes a
  `csrf_token` to every view. Added the hidden token field to all real POST forms
  (vote, save/hide, comment create/reply/edit/delete, post edit/delete, crosspost,
  mod remove, subscribe, create-subreddit, submit, logout). The login/register
  actions dropped their now-redundant inline CSRF handling.
- **Password reset** — `GET/POST /password` issues a one-shot, 1-hour token
  (`password_resets` table, migration `[17]`; CSPRNG via `openssl.rand`); a
  matching `models/password_resets`. `GET/POST /password/reset?token=…` validates
  the token and sets a new bcrypt password, then signs the user in. No mail server
  in dev, so the link is surfaced on the page (would be emailed in prod) and the
  "no such account" response is generic.
- **Re-hashed seeded demo users** — old seeds stored the demo password (`hunter2`)
  in plaintext, which bcrypt rejected, so seeded users could never log in. Seed
  migration `[14]` now bcrypt-hashes at creation, and idempotent migration `[50]`
  re-hashes any leftover plaintext passwords in an existing DB (skips bcrypt
  hashes and the blank anonymous_coward password).
- **Submit preview** — the submit form gained a *Preview* button that renders the
  self-post Markdown (and keeps the entered fields) without creating the post.
  Submit errors are now shown on the page.
- **Simple pages for all routes** — added `/about`, `/faq`, `/help`, `/contact`
  (one `actions/static` over the shared `page` view), a logged-in **log out**
  control + username in the header, and fixed dead header/footer links
  (`/comments`, `/subs/mine/`, `/help/`, the empty `about`/`contact` hrefs).
- Specs: full password-reset flow (issue → reset → login, mismatch keeps token,
  invalid token, no account-existence leak), the re-hash migration, submit
  preview, site-wide CSRF rejection, the static pages, and logout. (137 specs.)

### Crossposts, image posts & thumbnails
- **Image thumbnails** — a new pure `utils/media` classifies a link as an image
  by extension (jpg/png/gif/webp/svg/avif/…, query-string tolerant). `submit`
  stores the image URL as `posts.thumbnail`; listings and the post page render
  an `<img>` preview. (`posts.thumbnail` added to migration `[4]` and the
  `get_listing`/`search` SELECTs.)
- **Crossposts** — `POST /post/:id/crosspost` (form: subreddit) re-shares a post
  into another subreddit, copying title/url/body/thumbnail and linking back via
  the new `posts.crosspost_parent_id` (self-FK). The post page shows a
  "crossposted from /r/…" tagline and a crosspost form for logged-in users.
  Chains are kept one level deep (a crosspost-of-a-crosspost points at the root).
- Pure-Lua specs for `media`; Docker integration specs for image thumbnails
  (set + rendered, non-image → none) and crossposts (attribution + chain depth).

### Spam filtering (lapis-bayes)
- **Wired up the previously-unused `lapis-bayes` dependency** as a Bayesian spam
  filter. New `utils/spam`: a pure tokenizer (lowercase alphabetic runs), a small
  built-in spam/ham corpus + `train_defaults()`, and `is_spam(text)` that blocks
  only above a 0.95 confidence and **fails open** (untrained / unavailable / too
  short → never blocks). Hooked into post submission and comment creation.
- lapis-bayes is Postgres-oriented, so two adaptations were needed for SQLite:
  its default tokenizer uses `to_tsvector` (replaced by injecting our pure-Lua
  tokenizer via `opts.tokenize_text`), and its migrations use `serial` /
  `foreign_key` / a `NOT NULL total_count` with no default (broken on SQLite) —
  so migration `[12]` creates the `lapis_bayes_*` tables with SQLite-safe types
  + defaults and trains the corpus.
- A `MIN_TOKENS` guard skips classifying short text (a 2–3 word link title can't
  be judged) — this prevents false positives on link posts; the URL itself is
  not fed to the text classifier. Covered by pure-Lua specs (tokenizer +
  fail-open) and Docker integration specs (block spam / allow ham on submit +
  comment).

### Discoverability (sitemap / robots / well-known)
- **`GET /sitemap.xml`** — a real sitemaps.org `urlset` of the homepage, every
  (non-deleted) subreddit, and up to 500 recent posts, with `<lastmod>`. Built
  by a new pure `utils/sitemap` (5 unit specs) and served by `actions/sitemap`
  with host-absolute `loc`s via `self:build_url`.
- **`GET /robots.txt`** is now app-served (`actions/robots`) instead of a static
  file: it allows content, disallows the auth/action/non-content paths
  (`/login`, `/submit`, `/vote/`, `/search`, `/admin`, …) and emits an absolute
  `Sitemap:` line. Dropped the nginx `location /robots.txt` static block (and the
  static file) so the dynamic route wins.
- **`GET /.well-known/security.txt`** (and `/security.txt`) — RFC 9116 with
  `Contact` + a rolling future `Expires`.
- HTTP integration tests cover all three routes.

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
- **Test suite now at 127 specs** (model/SQL + full HTTP integration), all green,
  with luacov coverage and a clean luacheck (0/0).
- **luacheck** added to the rockspec, Docker image, and CI (a `luacheck app`
  step gates the build), configured via `.luacheckrc` (luajit + `ngx` global;
  busted std for specs). Fixed all findings — **0 warnings / 0 errors** across
  64 files (removed dead `require`s and unused locals).
- CI now runs, per push: super-linter, **stylua --check**, **luacheck**, the
  **busted** suite with **luacov coverage** (gated at 80%), and a Docker
  **build + `lapis migrate`** smoke test.
- **stylua** — a one-time repo-wide format (`.stylua.toml`: tabs, 100 columns;
  `.styluaignore` for vendored/generated files) standardizes the previously
  mixed tabs/4-space indentation, plus a `stylua --check app` CI job.
- **Coverage gate** — `.luacov` now excludes the disabled `api.lua` stubs, so
  the number reflects active code (~89%); CI fails if it drops below 80%.

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

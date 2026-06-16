--- Migrations
-- @script migrations

local db = require("lapis.db")
local read_json = require("src.utils.read_json")
local Lorem = require("src.utils.lorem")
-- local util = require("lapis.util")
local misc = require("src.utils.misc")

local schema = require("lapis.db.schema")
local types = schema.types

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Subscriptions = require("src.models.subscriptions")
local Users = require("src.models.users")

math.randomseed(os.clock() * 100000000000)

-- Locate a seed-data file (e.g. initial_subs.json) across the layouts we run in.
-- The file ships under the app tree at `app/data/`, but `lapis migrate` runs
-- from the app dir in dev/prod and from the repo root in CI, and an operator may
-- also drop a custom copy into the Fly persistent volume at /var/data. Try, in
-- order: an explicit override, the operator volume, then the shipped copy
-- relative to either cwd. Returns the first path that exists, or nil.
local function seed_path(name)
	local candidates = {}
	local override = os.getenv("PAGESIX_SEED_DIR")
	if override then
		candidates[#candidates + 1] = override .. "/" .. name
	end
	candidates[#candidates + 1] = "/var/data/" .. name -- operator volume
	candidates[#candidates + 1] = "data/" .. name -- cwd = app dir (lapis migrate)
	candidates[#candidates + 1] = "app/data/" .. name -- cwd = repo root (CI)
	for _, path in ipairs(candidates) do
		local f = io.open(path, "rb")
		if f then
			f:close()
			return path
		end
	end
	return nil
end

local opts = {}
opts["strict"] = true
opts["if_not_exists"] = true

-- add each incremental migration whose key is the unix timestamp
return {
	[1] = function()
		-- PRAGMA journal_mode=WAL
		local pragma = {
			journal_mode = "WAL",
			synchronous = "NORMAL",
			temp_store = "MEMORY",
			mmap_size = 1000000000,
			page_size = 32768,
		}

		for k, v in pairs(pragma) do
			db.query("PRAGMA " .. k .. "=" .. v)
		end

		-- db.query("PRAGMA journal_mode=WAL")
		-- db.query("PRAGMA synchronous=NORMAL")

		-- if (mode ~= "wal") then
		--     print ("Error setting WAL mode: " .. mode)
		--     os.exit()
		-- end
	end,

	-- create Users, User_Profiles & Subscriptions tables
	[2] = function()
		schema.create_table("users", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_name", types.text({ unique = true }) },
			{ "user_pass", types.text },
			{ "user_email", types.text },

			{ "created_at", types.text },
			{ "updated_at", types.text },

			{ "deleted_at", types.text({ null = true }) },
			{ "over_18", types.integer({ default = false }) },
			{ "verified_email", types.integer({ default = false }) },
		}, opts)

		schema.create_table("user_profiles", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_email", types.text },
			{ "description", types.text },

			{ "created_at", types.text },
			{ "updated_at", types.text },
			{ "deleted_at", types.text({ null = true }) },

			"FOREIGN KEY(id) REFERENCES users(id)",
		}, opts)

		schema.create_index("users", "user_name", { unique = true })

		schema.create_table("subscriptions", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer },
			{ "subreddit_id", types.integer },

			{ "created_at", types.text },
			{ "updated_at", types.text },

			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"FOREIGN KEY(subreddit_id) REFERENCES forum(id)",

			"UNIQUE(user_id, subreddit_id)",
		}, opts)

		schema.create_table("reserved_usernames", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_name", types.text({ unique = true }) },

			{ "created_at", types.text({ null = true }) },
			{ "updated_at", types.text({ null = true }) },
		}, opts)

		-- Names that must never be registered (route/UI collisions + impersonation).
		-- The Users `user_name` constraint checks this table on create.
		for _, name in ipairs({
			"admin",
			"administrator",
			"root",
			"mod",
			"moderator",
			"mods",
			"pagesix",
			"system",
			"support",
			"help",
			"null",
			"deleted",
			"anonymous",
			"everyone",
			"all",
			"popular",
			"random",
		}) do
			db.insert("reserved_usernames", { user_name = name })
		end
	end,

	-- create Forum table
	[3] = function()
		schema.create_table("forum", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "name", types.text({ unique = true }) },

			{ "created_at", types.text },
			{ "deleted_at", types.text({ null = true }) },
			{ "updated_at", types.text },

			{ "creator_id", types.integer({ default = 1 }) },
			{ "description", types.text({ null = true }) },
			{ "nsfw", types.integer({ default = false }) },
			{ "feeds", types.text({ null = true }) },

			"FOREIGN KEY(creator_id) REFERENCES users(id)",
		}, opts)

		-- create_index("subreddits", "name", { unique = true })
	end,

	-- create Posts, Comments & Votes tables
	[4] = function()
		-- create subreddit's table containing Posts by Users
		schema.create_table("posts", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer },
			{ "sub_id", types.integer },

			{ "title", types.text },
			{ "url", types.text({ null = true }) }, -- null for self/text posts
			-- { "domain", types.TEXT, "GENERATED ALWAYS AS (url_host(url)) VIRTUAL"},
			{ "created_at", types.text },
			{ "updated_at", types.text },

			{ "locked", types.integer({ default = false }) },
			{ "edited", types.integer({ default = false }) },
			{ "is_self", types.integer({ default = false }) },
			{ "over_18", types.integer({ default = false }) },
			{ "body", types.text({ null = true }) },

			-- Image link thumbnail (the image URL itself); null for non-image
			-- posts. `crosspost_parent_id` points at the original post a
			-- crosspost was made from.
			{ "thumbnail", types.text({ null = true }) },
			{ "crosspost_parent_id", types.integer({ null = true }) },

			"FOREIGN KEY(sub_id) REFERENCES forum(id)",
			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"FOREIGN KEY(crosspost_parent_id) REFERENCES posts(id)",
		}, opts)

		-- create subreddit's table containing Comments by Users
		schema.create_table("comments", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "post_id", types.integer },
			{ "user_id", types.integer },
			-- { "permalink", types.text({ unique = true }) },
			{ "parent_comment_id", types.integer({ null = true }) },
			{ "body", types.text },

			{ "created_at", types.text },
			{ "updated_at", types.text },

			{ "edited", types.integer({ default = false }) },
			{ "deleted", types.integer({ default = false }) },
			{ "is_submitter", types.integer({ default = false }) },
			{ "stickied", types.integer({ default = false }) },

			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"FOREIGN KEY(post_id) REFERENCES posts(id)",

			"UNIQUE(user_id, post_id, parent_comment_id)",
		}, opts)

		-- create each subreddit table containing Votes on Posts or Comments by Users
		schema.create_table("votes", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer },
			{ "post_id", types.integer },
			{ "comment_id", types.integer({ null = true }) },
			{ "upvote", types.integer({ default = true }) },

			{ "created_at", types.text },
			{ "updated_at", types.text },

			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"FOREIGN KEY(post_id) REFERENCES posts(id)",
			"FOREIGN KEY(comment_id) REFERENCES comments(id)",

			"UNIQUE(user_id, post_id, comment_id)",
		}, opts)

		schema.create_table("modlog", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "mod_id", types.integer },
			-- Denormalized from post.sub_id on purpose: this is an append-only
			-- audit log, and sub_id is the natural key for sub/comment-level
			-- actions (no post_id) and survives a post being hard-deleted.
			{ "sub_id", types.integer({ null = true }) },
			{ "post_id", types.integer({ null = true }) },
			{ "comment_id", types.integer({ null = true }) },
			{ "action", types.integer({ null = true }) },
			{ "reason", types.text },

			{ "created_at", types.text },
			{ "updated_at", types.text },

			"FOREIGN KEY(mod_id) REFERENCES users(id)",
			"FOREIGN KEY(sub_id) REFERENCES forum(id)",
			"FOREIGN KEY(post_id) REFERENCES posts(id)",
			"FOREIGN KEY(comment_id) REFERENCES comments(id)",
		}, opts)
	end,

	-- Performance indexes on the foreign keys the listing / thread / vote-count
	-- queries filter and join on. The UNIQUE constraints only index their
	-- leading column (e.g. user_id), which those aggregate subqueries don't
	-- filter by, so dedicated single-column indexes are still needed.
	[5] = function()
		local idx = { if_not_exists = true }
		schema.create_index("posts", "sub_id", idx)
		schema.create_index("posts", "user_id", idx)
		schema.create_index("posts", "created_at", idx)
		schema.create_index("comments", "post_id", idx)
		schema.create_index("comments", "parent_comment_id", idx)
		schema.create_index("comments", "user_id", idx)
		-- thread CTE anchor: WHERE post_id = ? AND parent_comment_id IS NULL
		schema.create_index("comments", "post_id", "parent_comment_id", idx)
		schema.create_index("votes", "post_id", idx)
		schema.create_index("votes", "comment_id", idx)
		schema.create_index("votes", "user_id", idx)
		schema.create_index("subscriptions", "subreddit_id", idx)

		-- Covering indexes so the per-row vote-count subqueries in get_listing /
		-- thread are index-only (no table lookups): they filter on
		-- (post_id|comment_id, upvote).
		schema.create_index("votes", "post_id", "comment_id", "upvote", idx)
		schema.create_index("votes", "comment_id", "upvote", idx)
	end,

	-- soft-delete flag for posts (comments already have one)
	[6] = function()
		schema.add_column("posts", "deleted", types.integer({ default = false }))
		schema.create_index("posts", "deleted", { if_not_exists = true })
		-- Partial index matching the listing filter (get_listing always does
		-- WHERE locked = 0 AND deleted = 0), ordered by recency: smaller than a
		-- full index and a tight match for the hot-path query.
		schema.create_index(
			"posts",
			"sub_id",
			"created_at",
			{ if_not_exists = true, where = "deleted = 0 AND locked = 0" }
		)
	end,

	-- full-text search over posts (SQLite FTS5), kept in sync by triggers
	[7] = function()
		db.query([[
            CREATE VIRTUAL TABLE IF NOT EXISTS posts_fts
            USING fts5(title, body, content='posts', content_rowid='id')
        ]])
		db.query([[
            CREATE TRIGGER IF NOT EXISTS posts_fts_ai AFTER INSERT ON posts BEGIN
                INSERT INTO posts_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
        ]])
		db.query([[
            CREATE TRIGGER IF NOT EXISTS posts_fts_ad AFTER DELETE ON posts BEGIN
                INSERT INTO posts_fts(posts_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
            END
        ]])
		db.query([[
            CREATE TRIGGER IF NOT EXISTS posts_fts_au AFTER UPDATE ON posts BEGIN
                INSERT INTO posts_fts(posts_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
                INSERT INTO posts_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
        ]])
		-- backfill any posts that already exist
		db.query("INSERT INTO posts_fts(rowid, title, body) SELECT id, title, body FROM posts")
	end,

	-- per-user saved and hidden posts
	[8] = function()
		for _, name in ipairs({ "saved_posts", "hidden_posts" }) do
			schema.create_table(name, {
				{ "id", types.integer({ unique = true, primary_key = true }) },
				{ "user_id", types.integer },
				{ "post_id", types.integer },
				{ "created_at", types.text },
				{ "updated_at", types.text },
				"FOREIGN KEY(user_id) REFERENCES users(id)",
				"FOREIGN KEY(post_id) REFERENCES posts(id)",
				"UNIQUE(user_id, post_id)",
			}, opts)
			schema.create_index(name, "user_id", { if_not_exists = true })
		end
	end,

	-- reply notifications (inbox). `seen` avoids the SQL keyword `read`.
	[9] = function()
		schema.create_table("notifications", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer }, -- recipient
			{ "comment_id", types.integer }, -- the reply comment
			{ "kind", types.text }, -- post_reply | comment_reply
			{ "seen", types.integer({ default = false }) },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"FOREIGN KEY(comment_id) REFERENCES comments(id)",
		}, opts)
		schema.create_index("notifications", "user_id", { if_not_exists = true })
	end,

	-- create first User
	[10] = function()
		Users:create({
			user_name = "anonymous_coward",
			user_email = "anonymous@localhost",
			user_pass = "",
		})
	end,

	-- moderators join table (replaces the forum.moderator_ids CSV)
	[11] = function()
		schema.create_table("moderators", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "subreddit_id", types.integer },
			{ "user_id", types.integer },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(subreddit_id) REFERENCES forum(id)",
			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"UNIQUE(subreddit_id, user_id)",
		}, opts)
		schema.create_index("moderators", "user_id", { if_not_exists = true })
	end,

	-- lapis-bayes spam-classifier tables + initial training. lapis-bayes ships
	-- its own migrations, but they're Postgres-shaped (serial / foreign_key /
	-- NOT NULL total_count with no default) and break on SQLite, so we create
	-- the tables the models expect here with SQLite-safe types + defaults.
	[12] = function()
		schema.create_table("lapis_bayes_categories", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "name", types.text },
			{ "total_count", types.integer({ default = 0 }) },
			{ "created_at", types.text({ null = true }) },
			{ "updated_at", types.text({ null = true }) },
		}, opts)
		schema.create_index("lapis_bayes_categories", "name", { if_not_exists = true })

		schema.create_table("lapis_bayes_word_classifications", {
			{ "category_id", types.integer },
			{ "word", types.text },
			{ "count", types.integer({ default = 0 }) },
			{ "created_at", types.text({ null = true }) },
			{ "updated_at", types.text({ null = true }) },
			"FOREIGN KEY(category_id) REFERENCES lapis_bayes_categories(id)",
			"PRIMARY KEY(category_id, word)",
		}, opts)

		require("src.utils.spam").train_defaults()
	end,

	-- create initial subreddits
	[13] = function()
		local path = seed_path("initial_subs.json")
		local data = (path and read_json(path)) or {}
		if #data > 0 then
			print("Read in " .. #data .. " subreddits from " .. path)
		else
			print(
				"No initial_subs.json found (checked $PAGESIX_SEED_DIR, /var/data, ./data, app/data); skipping subreddit seed"
			)
		end

		for _, sub in ipairs(data) do
			print("About to create new sub: " .. sub.name .. ".")

			local feeds_str = ""
			if sub.feeds ~= nil then
				for _, feed_url in pairs(sub.feeds) do
					feeds_str = feed_url .. "," .. feeds_str
					print("sub " .. sub.name .. " has feed_url " .. feed_url)
				end

				-- sub.feeds =
				print(feeds_str)
			end

			local s, e = Forum:create({
				name = sub.name,
				description = sub.description or Lorem:sentence(),
				creator_id = sub.creator_id or 1,
				feeds = feeds_str,
			})

			if not s then
				print("error creating " .. sub.name)
				print(e)
			end
		end
	end,

	-- create Users with random user_names
	[14] = function()
		local Password = require("src.utils.password")
		local subreddits = Forum:select()

		for i = 1, math.random(10, 100) do
			local name = Lorem:word() .. "_" .. i
			local s, e = Users:create({
				user_name = name,
				user_email = name .. "@localhost",
				-- Demo login: username + "hunter2". Hash it like a real signup so
				-- the seeded users can actually log in (bcrypt, never plaintext).
				user_pass = Password.hash("hunter2"),
			})
			if not s then
				print("error creating " .. name)
				print(e)
				break
			end

			for j = 1, #subreddits do
				if math.random(2) > 1 then
					-- Use the real row ids, not the loop counters (which only
					-- coincide with ids on a pristine, in-order database).
					Subscriptions:create({
						user_id = s.id,
						subreddit_id = subreddits[j].id,
					})
				end
			end
		end
	end,

	-- loop through all Subreddits and create some Posts for each
	[15] = function()
		local subreddits = Forum:select()

		-- ipairs: `sub` is the row. `for x in pairs(t)` would bind the index.
		for _, sub in ipairs(subreddits) do
			misc:generate_posts(sub.id, math.random(1, 3))
		end
	end,

	-- rss feed
	[16] = function()
		local subreddits = Forum:select()

		for _, sub in ipairs(subreddits) do
			if sub.feeds and #sub.feeds ~= 0 then
				for feed_url in string.gmatch(sub.feeds, "([^,]+)") do
					-- RSS fetches hit the network; never let one failed feed
					-- abort the whole migration.
					local ok, err = pcall(function()
						misc:rss_feed(sub.name, feed_url)
					end)
					if not ok then
						print(
							"rss_feed failed for "
								.. sub.name
								.. " ("
								.. feed_url
								.. "): "
								.. tostring(err)
						)
					end
				end
			end
		end
	end,

	-- password reset tokens (one-shot, time-limited). A row is created when a
	-- user requests a reset and deleted once consumed or expired.
	[17] = function()
		schema.create_table("password_resets", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer },
			{ "token", types.text({ unique = true }) },
			{ "expires_at", types.text },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(user_id) REFERENCES users(id)",
		}, opts)
		schema.create_index("password_resets", "token", { unique = true, if_not_exists = true })
		schema.create_index("password_resets", "user_id", { if_not_exists = true })
	end,

	-- moderation: sticky a post to the top of its subreddit, and lock its
	-- comment thread (no new comments/replies). Separate from `locked`, which
	-- the remove/approve flow uses to hide a post from listings.
	[18] = function()
		schema.add_column("posts", "stickied", types.integer({ default = false }))
		schema.add_column("posts", "comments_locked", types.integer({ default = false }))
		schema.create_index("posts", "sub_id", "stickied", { if_not_exists = true })
	end,

	-- live RSS import: per-feed rows (with fetch state) + a dedup key on posts.
	-- Promotes the legacy forum.feeds CSV into a real table the importer drives.
	[19] = function()
		schema.create_table("feeds", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "sub_id", types.integer },
			{ "url", types.text },
			{ "enabled", types.integer({ default = true }) },
			{ "last_fetched_at", types.text({ null = true }) },
			{ "last_status", types.text({ null = true }) },
			{ "failure_count", types.integer({ default = 0 }) },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(sub_id) REFERENCES forum(id)",
			"UNIQUE(sub_id, url)",
		}, opts)
		schema.create_index("feeds", "sub_id", { if_not_exists = true })

		-- Dedup key for imported posts: the feed entry's guid/link. Null for
		-- native (user-submitted) posts.
		schema.add_column("posts", "external_guid", types.text({ null = true }))
		schema.create_index("posts", "external_guid", { if_not_exists = true })
	end,

	-- Conditional-GET validators for the in-process scheduler: cache the last
	-- response's ETag / Last-Modified so the next fetch can send
	-- If-None-Match / If-Modified-Since and skip unchanged feeds (304).
	[21] = function()
		schema.add_column("feeds", "etag", types.text({ null = true }))
		schema.add_column("feeds", "last_modified", types.text({ null = true }))
	end,

	-- cast Votes on posts in each subreddit
	[20] = function()
		local posts = Posts:select()

		for _, post in ipairs(posts) do
			misc:generate_post_votes(post.id, math.random(5, 20))
		end
	end,

	-- create Comments on each post
	[30] = function()
		local posts = Posts:select()

		for _, post in ipairs(posts) do
			misc:generate_comments(post.id, math.random(5))
		end
	end,

	-- create 10 votes on each comment
	[40] = function()
		local posts = Posts:select()

		for _, post in ipairs(posts) do
			misc:generate_comment_votes(post.id, math.random(10))
		end
	end,

	-- Re-hash any plaintext passwords left by earlier seed runs. Old seeds
	-- stored "hunter2" verbatim, which bcrypt verify rejects, so those demo
	-- users could never log in. bcrypt digests start with "$2"; anything else
	-- (and non-empty -- anonymous_coward keeps its blank, unusable password) is
	-- a legacy plaintext value we re-hash in place. Idempotent: a second run
	-- finds only "$2..." hashes and does nothing.
	[50] = function()
		local Password = require("src.utils.password")
		local users = Users:select("WHERE user_pass != '' AND user_pass NOT LIKE '$2%'")
		for _, user in ipairs(users) do
			user:update({ user_pass = Password.hash(user.user_pass) })
		end
		print("re-hashed " .. #users .. " legacy plaintext password(s)")
	end,

	-- Promote the legacy forum.feeds CSV into the feeds table so the live
	-- importer has per-feed rows to work from. Idempotent (Feeds:add dedups).
	[60] = function()
		local Feeds = require("src.models.feeds")
		for _, sub in ipairs(Forum:select()) do
			if sub.feeds and sub.feeds ~= "" then
				for url in string.gmatch(sub.feeds, "([^,]+)") do
					url = url:match("^%s*(.-)%s*$")
					if url ~= "" then
						Feeds:add(sub.id, url)
					end
				end
			end
		end
	end,

	[99] = function()
		-- Gather statistics so the query planner picks the right indexes for
		-- the now-populated tables.
		db.query("ANALYZE")
	end,

	-- RBAC: generalized per-forum roles (owner/moderator/member) plus global
	-- site roles (admin). Supersedes the binary `moderators` join table for
	-- permission checks -- see src/utils/privileges.lua. The `moderators` table
	-- is left intact; its rows are backfilled here so nothing is lost.
	[100] = function()
		schema.create_table("roles", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "subreddit_id", types.integer },
			{ "user_id", types.integer },
			{ "role", types.text },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(subreddit_id) REFERENCES forum(id)",
			"FOREIGN KEY(user_id) REFERENCES users(id)",
			-- One role per user per forum (owner > moderator > member).
			"UNIQUE(subreddit_id, user_id)",
		}, opts)
		schema.create_index("roles", "subreddit_id", "user_id", { if_not_exists = true })

		schema.create_table("site_roles", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "user_id", types.integer },
			{ "role", types.text },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(user_id) REFERENCES users(id)",
			"UNIQUE(user_id, role)",
		}, opts)
		schema.create_index("site_roles", "user_id", { if_not_exists = true })

		-- Backfill: every forum creator is an owner; every moderators row is a
		-- moderator. Owners are assigned first so a creator who also sits in the
		-- moderators table keeps the higher role (Roles:assign is create-if-absent).
		local Roles = require("src.models.roles")
		for _, forum in ipairs(Forum:select()) do
			Roles:assign(forum.id, forum.creator_id, "owner")
		end
		for _, m in ipairs(db.select("subreddit_id, user_id FROM moderators")) do
			Roles:assign(m.subreddit_id, m.user_id, "moderator")
		end
	end,

	-- Admin Control Panel: runtime key/value site settings (see
	-- src/models/site_settings.lua), editable from /admin/settings.
	[101] = function()
		schema.create_table("site_settings", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "key", types.text({ unique = true }) },
			{ "value", types.text({ null = true }) },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"UNIQUE(key)",
		}, opts)
	end,

	-- Cached user reputation (net vote score). Persists what Users:karma()
	-- computes live so it can be surfaced cheaply and gate features (trust
	-- levels). Recomputed on each vote; backfilled here from existing votes.
	[102] = function()
		-- Idempotent: add_column throws "duplicate column" on a second run, so
		-- only add it when absent. The backfill below is always safe to repeat.
		local has_col = false
		for _, c in ipairs(db.query("PRAGMA table_info(users)")) do
			if c.name == "reputation" then
				has_col = true
			end
		end
		if not has_col then
			schema.add_column("users", "reputation", types.integer({ default = 0 }))
		end
		for _, user in ipairs(Users:select()) do
			Users:recompute_reputation(user.id)
		end
	end,

	-- Post/comment approval queue. `approved` defaults to 1 so all existing
	-- content stays visible; new content from brand-new users is created with
	-- approved = 0 and held for a moderator (see src/utils/queue.lua). Listings,
	-- search, and threads filter approved = 1.
	[103] = function()
		for _, t in ipairs({ "posts", "comments" }) do
			-- Idempotent: only add the column when it's absent.
			local has_col = false
			for _, c in ipairs(db.query("PRAGMA table_info(" .. t .. ")")) do
				if c.name == "approved" then
					has_col = true
				end
			end
			if not has_col then
				schema.add_column(t, "approved", types.integer({ default = 1 }))
			end
		end
		schema.create_index("posts", "sub_id", "approved", { if_not_exists = true })
		schema.create_index("comments", "post_id", "approved", { if_not_exists = true })
	end,

	-- Tags: a flat tag vocabulary and a post<->tag join (see src/models/tags.lua).
	[104] = function()
		schema.create_table("tags", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "name", types.text({ unique = true }) },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"UNIQUE(name)",
		}, opts)
		schema.create_table("post_tags", {
			{ "id", types.integer({ unique = true, primary_key = true }) },
			{ "post_id", types.integer },
			{ "tag_id", types.integer },
			{ "created_at", types.text },
			{ "updated_at", types.text },
			"FOREIGN KEY(post_id) REFERENCES posts(id)",
			"FOREIGN KEY(tag_id) REFERENCES tags(id)",
			"UNIQUE(post_id, tag_id)",
		}, opts)
		schema.create_index("post_tags", "post_id", { if_not_exists = true })
		schema.create_index("post_tags", "tag_id", { if_not_exists = true })
	end,

	-- classify text : https://github.com/leafo/lapis-bayes
	[1439944992] = require("lapis.bayes.schema").run_migrations,
}

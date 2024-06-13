--- Subreddits model
-- @module models.subreddit

local db = require("lapis.db")
local schema = require("lapis.db.schema")
local types = schema.types

local Model = require("lapis.db.model").Model

print("RUNNING MODELS.SUBREDDITS")

local Subreddits, Subreddits_mt = Model:extend("subreddits", {
	-- primary_key = "id",
	timestamp = true,
	relations = {
		{ "posts", has_many = "Posts" },
		{ "moderators", has_many = "Users" },
		{ "creator", belongs_to = "Users" },
	},

	constraints = {
		--- Apply constraints when updating/inserting a Subreddit row, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		name = function(self, value)
			-- is subreddit name taken?
			-- is subreddit not-empty?

			local reserved_subreddit_names = {
				"all",
				"popular",
				"random",
				"subscribed",
				"unsubscribed",
			}
			if reserved_subreddit_names[value] then
				return "Subreddit name is reserved"
			end

			-- check for valid length (2-64]
			if string.len(value) >= 64 then
				return "Subreddits must be less than 64 characters"
			end

			if string.len(value) < 2 then
				return "Subreddits must be at least 2 characters"
			end
		end,
	},
})

-- TODO check if name is name is in subreddits:get_all()
-- @param text name
-- @treturn table
function Subreddits:should_exist(name)
	return db.query("SELECT name FROM subreddits WHERE name=?", name)
end

--- Check if subreddit table(s) exist
-- @tparam string name
-- @treturn boolean
function Subreddits:tables_exist(name)
	-- a subreddit has tables: $subreddit_{posts,comments,votes}
	local table_name = name .. "_posts"
	-- TODO ensure all tables exist
	return db.query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", table_name)
end

--- Create a subreddit
-- @tparam string id Subreddit name
-- @treturn boolean success
-- @treturn string error
function Subreddits_mt:create_db_tables(id)
	local posts_table = id .. "_posts"
	local comments_table = id .. "_comments"
	local votes_table = id .. "_votes"
	local modlog_table = id .. "_modlog"

	-- create subreddit table containing Posts by Users
	schema.create_table(posts_table, {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_id", types.text },
		{ "permalink", types.text({ unique = true }) },
		{ "title", types.text },
		{ "url", types.text },

		{ "locked", types.integer({ default = false }) },
		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },
		{ "edited", types.integer({ default = false }) },
		{ "is_self", types.integer({ default = false }) },
		{ "over_18", types.integer({ default = false }) },
		{ "body", types.text({ null = true }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
	})

	-- create subreddit table containing Comments by Users
	schema.create_table(comments_table, {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "post_id", types.integer },
		{ "user_id", types.integer },
		{ "parent_comment_id", types.integer({ null = true }) },
		{ "body", types.text },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },
		{ "edited", types.integer({ default = false }) },
		{ "deleted", types.integer({ default = false }) },
		{ "is_submitter", types.integer({ default = false }) },
		{ "stickied", types.integer({ default = false }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
		-- "FOREIGN KEY(post_id) REFERENCES '1_posts(id)'"
		"FOREIGN KEY(post_id) REFERENCES '" .. id .. "_posts(id)'"
	})

	-- create each subreddit table containing Votes on Posts or Comments by Users
	schema.create_table(votes_table, {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_id", types.integer },
		{ "post_id", types.integer },
		{ "comment_id", types.integer({ null = true }) },
		{ "upvote", types.integer({ default = true }) },
		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(post_id) REFERENCES '" .. id .. "_posts(id)'",
		"FOREIGN KEY(comment_id) REFERENCES '" .. id .. "_comments(id)'"
	})

	schema.create_table(modlog_table, {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "mod_id", types.text },
		{ "user_id", types.text({ null = true }) },
		{ "sub_id", types.text({ null = true }) }, -- TODO remove?
		{ "post_id", types.text({ null = true }) },
		{ "comment_id", types.text({ null = true }) },
		{ "action", types.integer({ null = true }) },
		{ "reason", types.text },
		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		"FOREIGN KEY(mod_id) REFERENCES users(id)", -- TODO
		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(post_id) REFERENCES '" .. id .. "_posts(id)'",
		"FOREIGN KEY(comment_id) REFERENCES '" .. id .. "_comments(id)'"
	})

	-- hot
	-- new
	-- rising
	-- controversial
		-- day
		-- week
		-- month
		-- year
		-- all
	-- top
		-- day
		-- week
		-- month
		-- year
		-- all

	local sorts = { "hot" }
	for _, sort in pairs(sorts) do
		db.query(
			[[
				CREATE VIEW IF NOT EXISTS ?
				AS
				SELECT COUNT(*) score, a.title, a.url, a.permalink, over_18, locked
				FROM ? a
				INNER JOIN ? b ON a.id=b.post_id
				WHERE a.locked = 0 AND b.comment_id IS NULL
				GROUP BY a.id, b.post_id
				ORDER BY COUNT(*) DESC;
			]],
			"v_" .. id .. "_" .. sort,
			id .. "_posts",
			id .. "_votes"
		)
	end
end

return Subreddits

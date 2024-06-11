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
	})

	schema.create_table(modlog_table, {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "mod_id", types.text },
		{ "user_id", types.text({ null = true }) },
		{ "sub_id", types.text({ null = true }) },
		{ "post_id", types.text({ null = true }) },
		{ "comment_id", types.text({ null = true }) },
		{ "action", types.integer({ null = true }) },
		{ "reason", types.text },
		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },
	})

	local subreddit_table_name = id .. "_posts"

	-- hot
	-- all
	-- new
	-- all
	-- rising
	-- all
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

	local sorts = { "hot", "new", "rising" }
	for k, v in pairs(sorts) do
		local view_name = "v_" .. id .. "_" .. v

		-- TODO add upvotes, downvotes
		db.query(
			[[
				CREATE VIEW IF NOT EXISTS ?
				AS
				SELECT id, title, url, user_id
				FROM ?
			]],
			view_name,
			subreddit_table_name
		)
	end

	-- local sorts2 = {"controversial", "top"}
	-- local t = {"day", "week", "month", "year", "all"}

	-- for j,u in pairs(sorts2) do
	-- 	for k,v in pairs(t) do
	-- 		local tbl = "v_" .. id .. "_" .. u .. "_" .. v
	-- 		db.query(
	-- 			[[
	-- 				CREATE VIEW IF NOT EXISTS ?
	-- 				AS
	-- 				SELECT id, title, url, user_id
	-- 				FROM ?
	-- 			]],
	-- 			tbl,
	-- 			subreddit_table_name)
	-- 	end
	-- end
end

return Subreddits

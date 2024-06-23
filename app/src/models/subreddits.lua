--- Subreddits model
-- @module models.subreddit

-- local db = require("lapis.db")
-- local schema = require("lapis.db.schema")
-- local types = schema.types

local Model = require("lapis.db.model").Model

print("RUNNING MODELS.SUBREDDITS")

-- local Subreddits, Subreddits_mt = Model:extend("subreddits", {
local Subreddits = Model:extend("subreddits", {
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
			local reserved_subreddit_names = {
				"admin",
				"all",
				"controversial",
				"mods",
				"new",
				"pagesix",
				"popular",
				"random",
				"subscribed",
				"unsubscribed"
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

return Subreddits

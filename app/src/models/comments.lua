--- Comments model
-- @module models.comments

local Model = require("lapis.db.model").Model

local Comments = Model:extend("comments", {
	timestamp = true,
	constraints = {
		--- Apply constraints when updating/adding a Comment, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		name = function(self, value)
			if value then
				if string.len(value.body) > 4096 then
					return "Comment must be less than 4096 characters"
				end
				if value.body == nil or value.body == "" then
					return "Comment cannot be empty"
				end
			-- else
			-- 	print("NOPE")
			end
		end,
	},
	relations = {
		-- A comment belongs to the user who wrote it (comments.user_id -> users.id).
		-- This was previously `has_one`, which looked for a non-existent
		-- comments.id reference on users and returned nil.
		{ "user", belongs_to = "Users" },
		{ "votes", has_many = "Votes" },
		-- { "parent_comment", belongs_to="Comments" },
		{ "post", belongs_to = "Posts" },
		-- NOTE: comments has no `subreddit_id` column, so `get_subreddit()`
		-- can't resolve. Reach the subreddit via the post instead
		-- (comment:get_post():get_subreddit()).
		-- { "subreddit", belongs_to = "Forum" },
	},
})

return Comments

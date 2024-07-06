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
		{ "user", has_one = "Users" },
		{ "votes", has_many = "Votes" },
		-- { "parent_comment", belongs_to="Comments" },
		{ "post", belongs_to = "Posts" },
		{ "subreddit", belongs_to = "Forum" },
	},
})

return Comments

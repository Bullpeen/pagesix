--- Votes model
-- @module models.votes

local Model     = require("lapis.db.model").Model
local Votes     = Model:extend("votes", {
	relations = {
		{ "post",    belongs_to = "Posts" },
		{ "comment", belongs_to = "Comments" },
		{ "user",    belongs_to = "Users" }
	}
})

-- TODO: {user_id, post_id, comment_id} tuple should be unique

--- Votes model
-- @module models.votes

local Model = require("lapis.db.model").Model

-- local Votes, Votes_mt = Model:extend("votes", {
local Votes = Model:extend("votes", {
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "comment", belongs_to = "Comments" },
		{ "user", belongs_to = "Users" },
	},
	constraints = {
		-- TODO: {user_id, post_id, comment_id} tuple should be unique to vote's table
	},
})

return Votes

--- Votes model
-- @module models.votes

local Model = require("lapis.db.model").Model

print("RUNNING MODELS.Votes ")

-- local Votes, Votes_mt = Model:extend("votes", {
local Votes = Model:extend("votes", {
	-- primary_key = "id",
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "comment", belongs_to = "Comments" },
		{ "user", belongs_to = "Users" },
	},
	constraints = {
		-- TODO: {user_id, post_id, comment_id} tuple should be unique to subreddit's table
	},
})

print("RUNNING MODELS.VOTE")

return Votes

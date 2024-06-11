--- Votes model
-- @module models.votes

local Model = require("lapis.db.model").Model

-- TODO
local id = 1

local votes_table = id .. "_votes"

print("RUNNING MODELS.Votes " .. votes_table)

local Votes, Votes_mt = Model:extend(votes_table, {
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

--- Votes model
-- @module models.votes

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Votes = Model:extend("votes", {
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "comment", belongs_to = "Comments" },
		{ "user", belongs_to = "Users" },
	},
	-- The schema enforces UNIQUE(user_id, post_id, comment_id); cast() keeps a
	-- user to a single vote per target.
})

--- Cast, change, or undo a user's vote on a post (or comment).
-- Voting the same direction twice removes the vote (Reddit-style toggle);
-- voting the other direction flips it.
-- @tparam number user_id
-- @tparam number post_id
-- @tparam number|nil comment_id nil for a post vote
-- @tparam number upvote 1 for up, 0 for down
-- @treturn table|nil the vote row, or nil if the vote was undone
function Votes:cast(user_id, post_id, comment_id, upvote)
	local existing = self:find({
		user_id = user_id,
		post_id = post_id,
		comment_id = comment_id or db.NULL,
	})

	if existing then
		if tonumber(existing.upvote) == upvote then
			existing:delete()
			return nil
		end
		existing:update({ upvote = upvote })
		return existing
	end

	return self:create({
		user_id = user_id,
		post_id = post_id,
		comment_id = comment_id,
		upvote = upvote,
	})
end

return Votes

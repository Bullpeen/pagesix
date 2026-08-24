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
	-- One vote per user per target is enforced by two *partial* unique indexes
	-- (migration [112]), not by the table's UNIQUE(user_id, post_id, comment_id)
	-- -- that one silently never fires for post votes, because SQLite treats the
	-- NULL comment_id as distinct. `upsert` below relies on the partial indexes
	-- as its conflict target.
})

--- Insert a vote, or update the existing one for the same target.
--
-- A single statement, so two workers racing on the same (user, target) cannot
-- both insert -- which a find-then-insert allowed. The conflict target has to
-- name the partial index's predicate so SQLite can match it.
-- @tparam table fields user_id, post_id, comment_id (may be nil), upvote
-- @treturn table the stored row
local function upsert(self, fields)
	local now = db.format_date()
	if fields.comment_id == nil then
		db.query(
			[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
				VALUES (?, ?, NULL, ?, ?, ?)
				ON CONFLICT (user_id, post_id) WHERE comment_id IS NULL
				DO UPDATE SET upvote = excluded.upvote, updated_at = excluded.updated_at]],
			fields.user_id,
			fields.post_id,
			fields.upvote,
			now,
			now
		)
	else
		db.query(
			[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
				VALUES (?, ?, ?, ?, ?, ?)
				ON CONFLICT (user_id, comment_id) WHERE comment_id IS NOT NULL
				DO UPDATE SET upvote = excluded.upvote, updated_at = excluded.updated_at]],
			fields.user_id,
			fields.post_id,
			fields.comment_id,
			fields.upvote,
			now,
			now
		)
	end
	return self:find({
		user_id = fields.user_id,
		post_id = fields.post_id,
		comment_id = fields.comment_id or db.NULL,
	})
end

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

	if existing and tonumber(existing.upvote) == upvote then
		existing:delete()
		return nil
	end

	return upsert(self, {
		user_id = user_id,
		post_id = post_id,
		comment_id = comment_id,
		upvote = upvote,
	})
end

--- Set a user's vote on a post (or comment) to an explicit direction.
-- Unlike cast() (which toggles for the web UI), this sets the exact state the
-- API's `dir` field asks for: 1 = upvote, -1 = downvote, 0 = no vote (remove).
-- Idempotent -- re-sending the same dir is a no-op.
-- @tparam number user_id
-- @tparam number post_id
-- @tparam number|nil comment_id nil for a post vote
-- @tparam number dir 1 (up), -1 (down), or 0 (remove)
-- @treturn table|nil the vote row, or nil when removed / unchanged-to-absent
function Votes:set(user_id, post_id, comment_id, dir)
	local existing = self:find({
		user_id = user_id,
		post_id = post_id,
		comment_id = comment_id or db.NULL,
	})

	if dir == 0 then
		if existing then
			existing:delete()
		end
		return nil
	end

	return upsert(self, {
		user_id = user_id,
		post_id = post_id,
		comment_id = comment_id,
		upvote = dir == 1 and 1 or 0,
	})
end

--- Net score (upvotes - downvotes) for a post's own votes (comment_id IS NULL).
-- @tparam number post_id
-- @treturn number
function Votes:post_score(post_id)
	local row = db.select(
		[[COALESCE(SUM(CASE WHEN upvote = 1 THEN 1 ELSE -1 END), 0) AS s
			FROM votes WHERE post_id = ? AND comment_id IS NULL]],
		tonumber(post_id)
	)
	return tonumber(row[1].s) or 0
end

--- Net score (upvotes - downvotes) for a single comment.
-- @tparam number comment_id
-- @treturn number
function Votes:comment_score(comment_id)
	local row = db.select(
		[[COALESCE(SUM(CASE WHEN upvote = 1 THEN 1 ELSE -1 END), 0) AS s
			FROM votes WHERE comment_id = ?]],
		tonumber(comment_id)
	)
	return tonumber(row[1].s) or 0
end

return Votes

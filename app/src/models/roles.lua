--- Per-forum roles (owner / moderator / member).
-- Source of truth for forum-scoped permission checks; see src/utils/privileges.lua.
-- Generalizes the legacy `moderators` join table: a moderator is just a row with
-- role = "moderator".
-- @module models.roles

local Model = require("lapis.db.model").Model

local Roles = Model:extend("roles", {
	timestamp = true,
	relations = {
		{ "subreddit", belongs_to = "Forum" },
		{ "user", belongs_to = "Users" },
	},
})

--- Assign a role to a user in a forum (create-if-absent, idempotent).
-- Does NOT downgrade or change an existing role -- callers that need to change a
-- role should delete and re-assign. Returns the role row, or nil on bad input.
-- @tparam number subreddit_id
-- @tparam number user_id
-- @tparam string role  "owner" | "moderator" | "member"
function Roles:assign(subreddit_id, user_id, role)
	if not subreddit_id or not user_id then
		return nil
	end
	local existing = self:find({ subreddit_id = subreddit_id, user_id = user_id })
	if existing then
		return existing
	end
	return self:create({ subreddit_id = subreddit_id, user_id = user_id, role = role })
end

--- The role string a user holds in a forum, or nil if they hold none.
-- @tparam number subreddit_id
-- @tparam number user_id
-- @treturn string|nil
function Roles:role_for(subreddit_id, user_id)
	if not subreddit_id or not user_id then
		return nil
	end
	local row = self:find({ subreddit_id = subreddit_id, user_id = user_id })
	return row and row.role or nil
end

return Roles

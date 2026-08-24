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

--- Usernames who moderate a forum: its owners and moderators, owners first.
-- The subreddit sidebar reads this. (Before the RBAC migration this lived in
-- the `moderators` join table, dropped in migration [113].)
-- @tparam number subreddit_id
-- @treturn table array of user names
function Roles:moderators(subreddit_id)
	if not subreddit_id then
		return {}
	end
	local db = require("lapis.db")
	local rows = db.select(
		[[u.user_name AS name FROM roles r
			INNER JOIN users u ON r.user_id = u.id
			WHERE r.subreddit_id = ? AND r.role IN ('owner', 'moderator')
			ORDER BY CASE r.role WHEN 'owner' THEN 0 ELSE 1 END, u.user_name]],
		tonumber(subreddit_id)
	)
	local names = {}
	for _, row in ipairs(rows) do
		names[#names + 1] = row.name
	end
	return names
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

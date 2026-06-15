--- Privilege matrix: the single entrypoint for "may this user do X in this forum?".
--
-- Generalizes the old binary Forum:can_moderate check into named privileges
-- mapped from a user's role. Resolution order:
--   1. a global site admin may do anything, in any forum;
--   2. otherwise the user's forum role (owner > moderator > member) is looked up
--      and the matrix below decides whether that role holds the privilege.
--
-- New moderator-ish features (post queue, accept-answer, admin) should call
-- Privileges.can(...) with a specific privilege rather than re-deriving roles.
-- @module utils.privileges

local Roles = require("src.models.roles")
local SiteRoles = require("src.models.site_roles")

-- Every privilege the system knows about. Kept as a list so the matrix below
-- (and tests) can reference the canonical set.
local ALL = {
	"remove", -- remove/approve a post from listings
	"lock", -- lock/unlock a comment thread
	"sticky", -- pin/unpin a post
	"approve", -- approve queued (held) posts/comments
	"manage_feeds", -- trigger RSS/Atom feed refreshes
	"accept_answer", -- mark a comment as the accepted answer
	"manage_mods", -- add/remove moderators
	"edit_forum", -- edit forum settings/description
	"ban", -- ban a user from the forum
}

local function set(list)
	local s = {}
	for _, p in ipairs(list) do
		s[p] = true
	end
	return s
end

-- role -> set of privileges. Owners get everything; moderators get the
-- day-to-day content powers but not the owner-only governance powers
-- (managing mods, editing the forum, banning); members get nothing.
local ROLE_PRIVILEGES = {
	owner = set(ALL),
	moderator = set({ "remove", "lock", "sticky", "approve", "manage_feeds", "accept_answer" }),
	member = {},
}

local Privileges = {}

Privileges.ALL = ALL
Privileges.ROLE_PRIVILEGES = ROLE_PRIVILEGES

--- Whether a user is a global site admin.
-- @tparam number user_id
-- @treturn boolean
function Privileges.is_admin(user_id)
	return user_id ~= nil and SiteRoles:is_admin(user_id)
end

--- The role a user holds in a forum: "owner", "moderator", or "member".
-- The forum creator is always treated as the owner (a safety net even if no
-- explicit owner role row exists), otherwise the roles table is consulted.
-- @tparam number user_id
-- @tparam table forum a forum row
-- @treturn string|nil role, or nil for bad input
function Privileges.role_of(user_id, forum)
	if not user_id or not forum then
		return nil
	end
	if forum.creator_id and tonumber(forum.creator_id) == tonumber(user_id) then
		return "owner"
	end
	return Roles:role_for(forum.id, user_id) or "member"
end

--- May this user perform `privilege` in this forum?
-- @tparam number user_id
-- @tparam table forum a forum row
-- @tparam string privilege one of Privileges.ALL
-- @treturn boolean
function Privileges.can(user_id, forum, privilege)
	if not user_id or not forum or not privilege then
		return false
	end
	-- Site admins override every forum-level check.
	if Privileges.is_admin(user_id) then
		return true
	end
	local privs = ROLE_PRIVILEGES[Privileges.role_of(user_id, forum)]
	return privs ~= nil and privs[privilege] == true
end

return Privileges

--- Global site roles (currently just "admin").
-- A site admin overrides every forum-level privilege check (see
-- src/utils/privileges.lua) and gates the Admin Control Panel.
-- @module models.site_roles

local Model = require("lapis.db.model").Model

local SiteRoles = Model:extend("site_roles", {
	timestamp = true,
	relations = {
		{ "user", belongs_to = "Users" },
	},
})

--- Grant a site role to a user (create-if-absent, idempotent).
-- @tparam number user_id
-- @tparam string role  defaults to "admin"
function SiteRoles:grant(user_id, role)
	if not user_id then
		return nil
	end
	role = role or "admin"
	local existing = self:find({ user_id = user_id, role = role })
	if existing then
		return existing
	end
	return self:create({ user_id = user_id, role = role })
end

--- Whether a user holds the global admin role.
-- @tparam number user_id
-- @treturn boolean
function SiteRoles:is_admin(user_id)
	if not user_id then
		return false
	end
	return self:find({ user_id = user_id, role = "admin" }) ~= nil
end

return SiteRoles

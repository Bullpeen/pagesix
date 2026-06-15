--- Admin Control Panel: user management (grant/revoke the site admin role).
-- @module action.admin_users

local Users = require("models.users")
local SiteRoles = require("src.models.site_roles")
local admin_guard = require("src.utils.admin_guard")

local function load_users(self)
	local users = Users:select("ORDER BY id ASC")
	for _, u in ipairs(users) do
		u.is_admin = SiteRoles:is_admin(u.id)
		u.karma = Users:karma(u.id)
	end
	self.users = users
end

return {
	before = function(self)
		local denied = admin_guard(self)
		if denied then
			return denied
		end
	end,

	GET = function(self)
		load_users(self)
		return { render = "admin.users" }
	end,

	-- POST /admin/users  (form: user_id, op = grant|revoke)
	POST = function(self)
		local target = self.params.user_id and Users:find(tonumber(self.params.user_id))
		if target then
			if self.params.op == "grant" then
				SiteRoles:grant(target.id, "admin")
			elseif self.params.op == "revoke" then
				-- Disallow self-revoke so an admin can't lock themselves out.
				if tonumber(target.id) ~= tonumber(self.current_user.id) then
					local row = SiteRoles:find({ user_id = target.id, role = "admin" })
					if row then
						row:delete()
					end
				end
			end
		end
		return { redirect_to = self:url_for("admin_users") }
	end,
}

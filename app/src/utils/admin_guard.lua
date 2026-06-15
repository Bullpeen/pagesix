--- Admin Control Panel access guard.
-- Use from an action's `before`: `local denied = admin_guard(self); if denied then
-- return denied end`. Redirects anonymous visitors to login and serves a bare 403
-- to logged-in non-admins. Returns nil when the current user is a site admin.
-- @module utils.admin_guard

local Privileges = require("src.utils.privileges")

return function(self)
	if not self.current_user then
		return self:write({ redirect_to = self:url_for("login") })
	end
	if not Privileges.ensure_admin(self.current_user) then
		return self:write({
			status = 403,
			layout = false,
			"Forbidden — the Admin Control Panel is restricted to site administrators.",
		})
	end
	return nil
end

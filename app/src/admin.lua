--- Admin Control Panel URLs (site-admin only; gated per-action by
--- src/utils/admin_guard).
-- @module src.admin

local r2 = require("lapis.application").respond_to

local function admin(app)
	app:match("admin", "/admin", r2(require("actions.admin")))
	app:match("admin_users", "/admin/users", r2(require("actions.admin_users")))
	app:match("admin_settings", "/admin/settings", r2(require("actions.admin_settings")))
	return app
end

return admin

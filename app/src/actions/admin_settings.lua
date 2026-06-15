--- Admin Control Panel: runtime site settings (key/value) editor.
-- @module action.admin_settings

local SiteSettings = require("src.models.site_settings")
local admin_guard = require("src.utils.admin_guard")

return {
	before = function(self)
		local denied = admin_guard(self)
		if denied then
			return denied
		end
	end,

	GET = function(self)
		self.settings = SiteSettings:all()
		return { render = "admin.settings" }
	end,

	-- POST /admin/settings  (form: key, value) -- upsert a single setting
	POST = function(self)
		local key = self.params.key and self.params.key:match("^%s*(.-)%s*$")
		if key and key ~= "" then
			SiteSettings:set(key, self.params.value or "")
		end
		return { redirect_to = self:url_for("admin_settings") }
	end,
}

--- Admin Control Panel: dashboard with site-wide counts.
-- @module action.admin

local db = require("lapis.db")
local admin_guard = require("src.utils.admin_guard")

local function count(table_name)
	return tonumber(db.select("COUNT(*) AS c FROM " .. table_name)[1].c) or 0
end

return {
	before = function(self)
		local denied = admin_guard(self)
		if denied then
			return denied
		end
		self.stats = {
			users = count("users"),
			forums = count("forum"),
			posts = count("posts"),
			comments = count("comments"),
			admins = count("site_roles WHERE role = 'admin'"),
		}
	end,

	GET = function(self)
		return { render = "admin.dashboard" }
	end,
}

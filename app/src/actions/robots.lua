--- robots.txt: allow content, keep crawlers out of auth/action/non-content
--- paths, and point at the sitemap.
-- @module action.robots

-- Paths with no crawl value (or that mutate state / require a session).
local DISALLOW = {
	"/login",
	"/register",
	"/logout",
	"/submit",
	"/vote/",
	"/inbox",
	"/saved",
	"/prefs",
	"/search",
	"/admin",
	"/console",
}

return {
	-- GET /robots.txt
	GET = function(self)
		local lines = { "User-agent: *" }
		for _, path in ipairs(DISALLOW) do
			lines[#lines + 1] = "Disallow: " .. path
		end
		lines[#lines + 1] = "Allow: /"
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Sitemap: " .. self:build_url("/sitemap.xml")

		return {
			content_type = "text/plain",
			layout = false,
			table.concat(lines, "\n") .. "\n",
		}
	end,
}

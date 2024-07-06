--- Domain action
-- @module action.domain

local db = require("lapis.db")

return {
	before = function(self)
		-- self.params.domain

		self.domain = self.params.domain

		-- Check if domain is nil or empty
		if self.domain == nil or self.domain == "" then
			print("Domain is unknown: " .. self.domain)
			-- return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- check if domain has a period anywhere in it
		if not string.find(self.domain, "%.") then
			print("Domain is invalid: " .. self.domain)
			-- return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- SELECT id FROM sometable WHERE url like '%domain%'
		self.posts = db.select("* FROM ? WHERE url LIKE ?", "v_hot_frontpage", "%" .. self.domain .. "%")
	end,

	GET = function(self)
		return { render = "domain" }
	end,
}

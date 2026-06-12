--- Domain action: list posts whose link points at a given domain.
-- @module action.domain

local Posts = require("models.posts")

return {
	before = function(self)
		self.domain = self.params.domain or ""

		-- A bare word with no dot isn't a domain; show nothing rather than
		-- matching every URL substring.
		if self.domain == "" or not string.find(self.domain, "%.") then
			self.posts = {}
			return
		end

		-- Canonical listing path (same vote/comment aggregates as everywhere
		-- else); the LIKE filter matches the host inside the stored URL.
		self.posts = Posts:get_listing({ domain = self.domain })
	end,

	GET = function(self)
		return { render = "domain" }
	end,
}

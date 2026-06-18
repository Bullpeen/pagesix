--- Domain action: list posts whose link points at a given domain.
-- @module action.domain

local Posts = require("models.posts")

return {
	before = function(self)
		-- Normalize to match the stored host (lowercased, leading www. stripped)
		-- so a hand-typed /domain/WWW.Example.com still resolves.
		self.domain = (self.params.domain or ""):lower():gsub("^www%.", "")

		-- A bare word with no dot isn't a domain; show nothing rather than
		-- matching every URL substring.
		if self.domain == "" or not string.find(self.domain, "%.") then
			self.posts = {}
			return
		end

		-- Canonical listing path (same vote/comment aggregates as everywhere
		-- else); the filter is an exact match on the stored posts.domain column.
		self.posts = Posts:get_listing({ domain = self.domain })
	end,

	GET = function(self)
		return { render = "domain" }
	end,
}

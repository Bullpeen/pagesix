--- Search action (full-text over posts)
-- @module action.search

local Posts = require("src.models.posts")

return {
	-- GET /search?q=...
	before = function(self)
		self.query = self.params.q
		self.posts = Posts:search(self.params.q)
	end,

	GET = function(self)
		-- Reuse the posts listing template to render results.
		return { render = "index" }
	end,
}

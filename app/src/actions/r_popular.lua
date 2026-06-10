--- /r/popular action
-- @module action.r_popular

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		-- "popular" is the cross-subreddit frontpage (same data as /), so it
		-- needs posts; previously it rendered the index template with no posts.
		self.posts = Sort:sort(Posts:get_listing(), sort)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

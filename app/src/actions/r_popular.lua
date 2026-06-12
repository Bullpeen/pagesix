--- /r/popular action
-- @module action.r_popular

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		-- "popular" is the cross-subreddit frontpage (same data as /), so it
		-- needs posts; previously it rendered the index template with no posts.
		local since = require("src.utils.timewindow")(self.params.t)
		local sorted = Sort:sort(Posts:get_listing({
			since = since,
			exclude_hidden_for = self.current_user and self.current_user.id,
		}), sort)
		self.posts, self.pagination = require("src.utils.paginate")(sorted, self.params.page)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

--- /r/popular action
-- @module action.r_popular

local Posts = require("src.models.posts")
local P = require("src.utils.paginate_db")

-- Posts per listing page.
local PER_PAGE = 25

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		-- "popular" is the cross-subreddit frontpage (same data as /), ranked
		-- and sliced in SQL (see Posts.get_listing's ORDER_BY).
		local since = require("src.utils.timewindow")(self.params.t)
		local page, per_page, limit, offset = P.window(self.params.page, PER_PAGE)
		local rows = Posts:get_listing({
			since = since,
			exclude_hidden_for = self.current_user and self.current_user.id,
			sort = sort,
			limit = limit,
			offset = offset,
		})
		self.posts, self.pagination = P.finish(rows, page, per_page)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

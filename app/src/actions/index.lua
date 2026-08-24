--- Index action
-- @module action.index

local Posts = require("src.models.posts")
local P = require("src.utils.paginate_db")

-- Posts per listing page.
local PER_PAGE = 25

return {
	before = function(self)
		local sort = self.params.sort or "hot" -- best, controversial, hot, top

		-- Frontpage: all subreddits. The database ranks and slices (see
		-- Posts.get_listing's ORDER_BY) so the page costs one bounded query
		-- instead of reading every matching post into Lua.
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

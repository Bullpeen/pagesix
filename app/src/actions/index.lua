--- Index action
-- @module action.index

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot" -- best, controversial, hot, top

		-- Frontpage: all subreddits. Posts:get_listing() computes vote/comment
		-- aggregates directly, so this works on a freshly-migrated DB and does
		-- not depend on the pre-seeded v_hot_frontpage view.
		local since = require("src.utils.timewindow")(self.params.t)
		local sorted = Sort:sort(Posts:get_listing({ since = since }), sort)
		self.posts, self.pagination = require("src.utils.paginate")(sorted, self.params.page)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

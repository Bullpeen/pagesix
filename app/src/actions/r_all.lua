--- /r/all action
-- @module action.index

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		-- Posts:select() returns bare rows without vote/comment aggregates,
		-- which Sort needs; get_listing() supplies them.
		local since = require("src.utils.timewindow")(self.params.t)
		local sorted = Sort:sort(Posts:get_listing({ since = since }), sort)
		self.posts, self.pagination = require("src.utils.paginate")(sorted, self.params.page)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

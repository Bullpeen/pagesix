--- /r/all action
-- @module action.index

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		-- Posts:select() returns bare rows without vote/comment aggregates,
		-- which Sort needs; get_listing() supplies them.
		self.posts = Sort:sort(Posts:get_listing(), sort)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

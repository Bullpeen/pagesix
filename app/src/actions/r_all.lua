--- /r/all action
-- @module action.index

local Posts = require("models.posts")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local sort = self.params.sort or "hot"
		self.posts = Sort:sort(Posts:select(), sort)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

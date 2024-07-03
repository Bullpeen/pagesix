--- /r/all action
-- @module action.index

local Posts = require("models.posts")

return {
	before = function(self)
		local posts = Posts:select()
		self.posts = posts
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

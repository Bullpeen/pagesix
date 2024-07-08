--- /r/popular subreddits action
-- @module action.index

-- local Forum = require("models.forum")
-- local Sort = require("src.utils.sort")

return {
	before = function(self)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

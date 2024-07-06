--- /r/popular subreddits action
-- @module action.index

-- local Forum = require("models.forum")

return {
	before = function(self)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

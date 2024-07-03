--- /r/popular subreddits action
-- @module action.index

local Forum = require("models.forum") "wtf"

return {
	before = function(self)
		-- TODO what does it mean to be 'popular'?

		-- local sub = Forum:find()
		-- require 'pl.pretty'.dump(sub)

		-- self.posts = sub:get_frontpage()
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

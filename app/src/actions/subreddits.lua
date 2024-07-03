--- Subreddits action
-- @module action.subreddits

local db = require("lapis.db")
-- local Forum = require("models.forum")

return {
	before = function(self)
		self.subs = db.select("* FROM ?", "v_forum")
		-- model doesn't track subscriber count
		-- self.subs = Forum:select()
	end,

	GET = function(self)
		return { render = "subreddits" }
	end,
}

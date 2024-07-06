--- Subreddits action
-- @module action.subreddits

local db = require("lapis.db")

return {
	before = function(self)
		self.subs = db.select("* FROM ?", "v_forum")
	end,

	GET = function(self)
		return { render = "subreddits" }
	end,
}

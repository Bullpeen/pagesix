--- Subreddits action
-- @module action.subreddits

local db = require("lapis.db")

return {
	before = function(self)
		-- Get list of all subs
		self.subs = db.select("* FROM ?", "subreddits")

	end,

	GET = function(self)
		return { render = "subreddits" }
	end,
}

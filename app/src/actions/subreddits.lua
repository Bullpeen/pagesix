--- Subreddits action
-- @module action.subreddits

local db = require "lapis.db"

return {
	before = function(self)
		-- Get list of all subs
		self.subs = db.select("* FROM ?", "subreddits")

		-- require 'pl.pretty'.dump(self.subs)
	end,

	GET = function(self)
		return { render = "subreddits" }
	end,
}

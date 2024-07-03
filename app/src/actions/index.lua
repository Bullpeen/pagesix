--- Index action
-- @module action.index

local db = require("lapis.db")

return {
	before = function(self)
		-- local paginated = Posts:paginated([[where group_id = ? order by name asc]], 123)
		self.posts = db.select("* FROM ? LIMIT ?", "v_hot_frontpage", 20)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

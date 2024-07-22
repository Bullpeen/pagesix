--- Index action
-- @module action.index

local db = require("lapis.db")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		-- self.params.sort
		local sort = self.params.sort or "hot" -- best, controversial, hot, new, rising, top

		-- print("SORTING BY " .. sort)

		-- local paginated = Posts:paginated([[where group_id = ? order by name asc]], 123)
		local posts = db.select("* FROM ? LIMIT ?", "v_hot_frontpage", 100)
		self.posts = Sort:sort(posts, sort)

	end,

	GET = function(self)
		return { render = "index" }
	end,
}

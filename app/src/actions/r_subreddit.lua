--- Subreddit action
-- @module action.subreddit

local Forum = require("models.forum")
local Sort = require("src.utils.sort")

return {
	before = function(self)
		local subreddit_name = self.params.subreddit
		local sort = self.params.sort or "hot"

		-- convert subreddit_id to name
		local subreddit_id = Forum.object_types:for_db(subreddit_name)

		local sub = Forum:find(subreddit_id)
		self.posts = Sort:sort(sub:get_frontpage(sub.name), sort)
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

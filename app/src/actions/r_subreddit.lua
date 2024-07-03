--- Subreddit action
-- @module action.subreddit

local Forum = require("models.forum")
-- local Posts = require("models.posts")

return {
	before = function(self)
		local subreddit_name = self.params.subreddit

		-- convert subreddit_id to name
		local subreddit_id = Forum.object_types:for_db(subreddit_name)

		-- print("subreddit_name " .. subreddit_name)
		-- print("subreddit_id " .. subreddit_id)

		local sub = Forum:find(subreddit_id)
		require 'pl.pretty'.dump(sub)

		self.posts = sub:get_frontpage()
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

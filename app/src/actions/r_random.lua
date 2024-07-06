--- Subreddit action
-- @module action.subreddit

local Forum = require("models.forum")

math.randomseed(os.clock() * 100000000000)

return {
	before = function(self)
		local subreddit_id = math.random(#Forum.object_types)

		local subreddit_name = Forum.object_types:to_name(subreddit_id)

		return self:write({ redirect_to = self:url_for("subreddit", { subreddit = subreddit_name }) })
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}
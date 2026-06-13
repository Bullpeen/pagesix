--- Random subreddit action
-- @module action.r_random

local Forum = require("src.models.forum")

return {
	before = function(self)
		-- Pick a real subreddit from the database. (The old code indexed the
		-- hardcoded object_types enum, which need not correspond to existing
		-- forum rows.)
		local sub = Forum:select("ORDER BY RANDOM() LIMIT 1")[1]
		if not sub then
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		return self:write({ redirect_to = self:url_for("subreddit", { subreddit = sub.name }) })
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

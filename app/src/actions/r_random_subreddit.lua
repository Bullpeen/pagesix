--- Subreddit action
-- @module action.subreddit

local db     = require "lapis.db"

return {
	before = function(self)
        -- query subreddits table for random subreddit
        local sub = db.query("SELECT name FROM subreddits ORDER BY RANDOM() LIMIT 1")

        local name = sub[1].name
        -- print("Random subreddit: " .. name)
        return self:write({ redirect_to = self:url_for("subreddit", {subreddit = name}) })
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit"}
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

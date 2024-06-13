--- Subreddit action
-- @module action.subreddit

local db = require("lapis.db")
local Subreddits = require("models.subreddits")

return {
	before = function(self)
		-- query subreddits table for random subreddit
		-- TODO use db.find(), avoid the [1] step?
		local sub = Subreddits:find(math.random(#Subreddits))
		-- local sub = db.query("SELECT name FROM subreddits ORDER BY RANDOM() LIMIT 1")

		print("Random subreddit: " .. sub.name)
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

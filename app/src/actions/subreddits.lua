--- Subreddits action
-- @module action.subreddits

local db = require("lapis.db")

return {
	before = function(self)
		-- /subreddits/search?q=... filters by name (typo-tolerant via sqlean's
		-- fuzzy extension; see Forum:search). A blank/absent query falls through
		-- to the full listing below.
		local q = self.params.q
		if q and q:match("%S") then
			self.query = q
			self.subreddits = require("src.models.forum"):search(q)
			return
		end

		-- List every subreddit with its subscriber count. The v_forum view only
		-- includes subs that already have a subscriber (INNER JOIN), so newly
		-- created subreddits never showed up; a LEFT-style subquery fixes that.
		-- NB: named `subreddits`, not `subs` -- the layout header reads `subs`
		-- for the logged-in user's subscriptions and would collide.
		self.subreddits = db.select([[
			s.name, s.description, s.nsfw,
			(SELECT COUNT(*) FROM subscriptions b WHERE b.subreddit_id = s.id) AS subscribers
			FROM forum s
			ORDER BY subscribers DESC, s.name ASC
		]])
	end,

	GET = function(self)
		return { render = "subreddits" }
	end,
}

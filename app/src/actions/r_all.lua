--- /r/all action
-- @module action.index

local db = require("lapis.db")

return {
	before = function(self)
		-- TODO
		-- materialized view(?) of /r/all, top N posts for TimePeriod across all Subreddits

		-- Get list of all subs
		-- self.subs = db.select("* FROM ?", "subreddits")
		-- Pagesix:get_all()

		-- view for /r/all subreddit posts
		local posts_table = "v_r_all_subreddit_posts"

		-- TODO subquery to return a table like
		-- {
		-- 		post_id: { title, url, user_id, created_at, is_self, body, upvotes, downvotes, num_comments },
		-- 		post_id: { ... },
		-- }

		self.posts = self:get_posts(posts_table)
		-- self.posts = db.select("* FROM ?", posts_table)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

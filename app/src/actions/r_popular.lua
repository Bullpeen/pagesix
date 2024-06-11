--- /r/popular subreddits action
-- @module action.index

return {
	before = function(self)
		local posts_table = "v_r_popular_subreddit_posts"
		self.posts = self:get_posts(posts_table)
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

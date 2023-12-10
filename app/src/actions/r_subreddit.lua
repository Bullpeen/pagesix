--- Subreddit action
-- @module action.subreddit

local db     = require "lapis.db"

return {
	before = function(self)
		local posts_table = ""
		if self.params.id then
			print("Subreddit id!!! " .. self.params.id)
			posts_table = id .. "_posts"
		else
			print("Subreddit name!!!")
			-- Check if subreddit is nil or empty
			local name = self.params.subreddit
			if name == nil or name == '' then
				print("Subreddit is unknown: " .. name)
				return self:write({ redirect_to = self:url_for("homepage") })
			end

			-- TODO write get_name_from_id()
			-- TODO limit 1
			local res = db.select("id FROM 'subreddits' WHERE name=?", name)
			if not res then
				print("Subreddit is invalid: " .. name)
				return self:write({ redirect_to = self:url_for("homepage") })
			end

			posts_table = res[1].id .. "_posts"
		end

		-- TODO subquery to return a table like
		-- {
		-- 		post_id: { title, url, user_id, created_at, is_self, body, upvotes, downvotes, num_comments },
		-- 		post_id: { ... },
		-- }

		-- self.posts = self:get_posts(posts_table)
		self.posts = db.select("* FROM ?", posts_table)
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit"}
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

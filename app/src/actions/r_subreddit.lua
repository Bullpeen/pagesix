--- Subreddit action
-- @module action.subreddit

local db = require("lapis.db")

return {
	before = function(self)
		-- Check if subreddit is nil or empty
		local name = self.params.subreddit
		if name == nil or name == "" then
			print("Subreddit is unknown: " .. name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- local res = Subreddits:find(id)
		local res = db.select("id FROM 'subreddits' WHERE name=? LIMIT 1", name)
		if not res then
			print("Subreddit is invalid: " .. name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- posts_table = res[1].id .. "_posts"
		local posts_table = "v_" .. res[1].id .. "_hot"
		-- print("looking up subreddit's posts using " .. posts_table)

		-- TODO subquery to return a table like
		-- {
		-- 		post_id: { title, url, user_id, created_at, is_self, body, upvotes, downvotes, num_comments },
		-- 		post_id: { ... },
		-- }

		-- self.posts = db.select("id, user_id, title, url FROM ?", posts_table)

		local data = {}
		-- for k,v in self.posts do
		-- 	data[v.id] = v.url
		-- end
		self.data = data

		-- self.posts = self:get_posts(posts_table)
		self.posts = db.select("* FROM ?", posts_table)
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

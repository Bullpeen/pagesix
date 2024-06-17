--- Post action
-- @module action.post

local db = require("lapis.db")

return {
	before = function(self)
		-- self.params.subreddit
		-- self.params.post_id
		-- ? self.params.title_stub

		-- Check if subreddit is nil or empty
		local sub_name = self.params.subreddit
		if sub_name == nil or sub_name == "" then
			print("Subreddit is unknown: " .. sub_name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- Get subreddit id from sub_name
		local res = db.select("id FROM 'subreddits' WHERE name=?", sub_name)
		local sub_id = res[1]["id"]
		local comments_table = sub_id .. "_comments"
		local posts_table = sub_id .. "_posts"

		-- TODO return table like, sorted by highest score (upvotes - downvotes)
		-- {
		-- 		comment_id: { body, user_id, created_at, edited, upvotes, downvotes, (parent_id) },
		--		comment_id: { ... },
		-- }

		-- self.comments = db.select("* FROM ? WHERE post_id = ?", comments_table, self.params.post_id)
		self.comments = db.select(
			[[
				COUNT(*) score, c.user_name, c.created_utc, b.user_id, b.body
				FROM ? a
				INNER JOIN ? b ON a.id=b.post_id
				INNER JOIN ? c ON b.user_id = c.id
				WHERE b.parent_comment_id IS NULL
				GROUP BY a.id, b.post_id
				ORDER BY COUNT(*) DESC;
			]],
			posts_table,
			comments_table,
			'users'
			)
		print("Found " .. #self.comments .. " comments")

		local post_data = db.select("* FROM ? WHERE id = ?", posts_table, self.params.post_id)
		print("Post data:")
		require 'pl.pretty'.dump(post_data[1])

		-- lookup user_name from user_id
		local user_name = db.query("SELECT user_name FROM 'users' WHERE id=?", post_data[1]["user_id"])
		print("User_name is " .. user_name[1]['user_name'])

		-- pass data to template
		self.user_name = user_name[1]['user_name']
		self.title = post_data[1]["title"]
		self.url = post_data[1]["url"]
		self.permalink = post_data[1]["permalink"]
		self.created_utc = post_data[1]["created_utc"]
		if post_data[1]["is_self"] == 1 then
			self.is_self = true
			self.body = post_data[1]["body"]
		end

	end,

	GET = function(self)
		return { render = "post" }
	end,
}

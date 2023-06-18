--- Post action
-- @module action.post

local db = require("lapis.db")

return {
	before = function(self)
		-- Check if subreddit is nil or empty
		local name = self.params.subreddit
		if name == nil or name == '' then
			print("Subreddit is unknown: " .. name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		local comments_table = name .. "_comments"
		self.comments = db.select("* FROM ? WHERE post_id = ?", comments_table, self.params.post_id)

		print("Found " .. #self.comments .. " comments")

		local posts_table = name .. "_posts"
		local post_data = db.select("* FROM ? WHERE id = ?", posts_table, self.params.post_id)
		-- print("Post data:")
		-- require 'pl.pretty'.dump(post_data[1])

		self.user_id = post_data[1]['user_id']
		self.title = post_data[1]['title']
		self.url = post_data[1]['url']
		self.permalink = post_data[1]['permalink']
		self.created_utc = post_data[1]['created_utc']

	end,

	GET = function(self)
		return { render = "post" }
	end
}

--- Comment action
-- @module action.comment

local db = require("lapis.db")

return {
	before = function(self)
		-- self.params.subreddit
		-- self.params.post_id
		-- self.params.title_stub
		-- self.params.comment_id
		-- ? self.params.q

		-- Check if subreddit is nil or empty
		local sub_name = self.params.subreddit
		if sub_name == nil or sub_name == '' then
			print("Subreddit is unknown: " .. sub_name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- Get subreddit id from sub_name
		local res = db.select("id FROM 'subreddits' WHERE name=?", sub_name)
		local id = res[1]['id']
		local comments_table = id .. "_comments"

		-- TODO return table like, sorted by highest score (upvotes - downvotes)
		-- {
		-- 		comment_id: { body, user_id, created_at, edited, upvotes, downvotes, (parent_id) },
		--		comment_id: { ... },
		-- }

		self.comments = db.select("* FROM ? WHERE id = ?", comments_table, self.params.comment_id)
		print("Found " .. #self.comments .. " comments (1)")

		-- TODO check context=N from url param, return that many (grand)parents in self.comments
		if self.params.q then
			local context = string.match(self.params.q, "%d+$")
		end
		if context ~= nil and context > 1 then
			-- loop context times and fetch each parent comments
			for i=1,context do
				-- if comment has a parent, fetch it
				if self.comments[i].parent_comment_id ~= nil then
					print("Looking up parent comment: " .. self.comments[i].parent_comment_id)
					local p = db.select("* FROM ? WHERE comment_id = ?", comments_table, self.comment[i].parent_comment_id)
					table.insert(self.comments, p[1])
				end
			end
		end

		local posts_table = id .. "_posts"
		local post_data = db.select("* FROM ? WHERE id = ?", posts_table, self.params.post_id)
		print("Post data:")
		require 'pl.pretty'.dump(post_data[1])

		-- lookup user_name from user_id
		local user_name = db.query("SELECT user_name FROM 'users' WHERE id=?", post_data[1]['user_id'])

		-- pass data to template
		self.user_name = user_name
		self.title = post_data[1]['title']
		self.url = post_data[1]['url']
		self.permalink = post_data[1]['permalink']
		self.created_utc = post_data[1]['created_utc']
	end,

	GET = function(self)
		return { render = "comment" }
	end
}

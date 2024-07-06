--- Post action
-- @module action.post

local Comments = require("models.comments")
local Forum = require("models.forum")
local Posts = require("models.posts")
local Users = require("models.users")

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

		-- print("Looking up " .. self.params.subreddit)
		local subreddit = Forum:find({name = self.params.subreddit})
		-- require 'pl.pretty'.dump(subreddit)
		if subreddit == nil then
			print("Subreddit is unknown: " .. sub_name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- TODO paginate
		self.comments = Comments:select("where post_id = ?", self.params.post_id)
		print("Found " .. #self.comments .. " comments")

		local post_data = Posts:find(self.params.post_id)
		print("Post data:")

		-- require 'pl.pretty'.dump(post_data[1])
		self.title = post_data["title"]
		self.url = post_data["url"]
		self.subreddit = self.params.subreddit
		self.post_id = self.params.post_id
		self.title_stub = self.params.title_stub
		self.permalink = post_data["permalink"]
		self.created_at = post_data["created_at"]
		if post_data["is_self"] == 1 then
			self.is_self = true
			self.body = post_data["body"]
		end

		-- local u = Posts:get_user()
		local u = Users:find(post_data["user_id"])
		print("User_name is " .. u['user_name'])
		self.user_name = u['user_name']

	end,

	GET = function(self)
		return { render = "post" }
	end,
}

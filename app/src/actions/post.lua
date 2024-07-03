--- Post action
-- @module action.post

local db = require("lapis.db")
local Comments = require("models.comments")
local Posts = require("models.posts")
local Forum = require("models.forum")
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

		-- self.comments = db.select(
		-- 	[[
		-- 		COUNT(*) score, c.user_name, c.created_at, b.user_id, b.body, b.permalink
		-- 		FROM 'posts' a
		-- 		INNER JOIN 'comments' b ON a.id=b.post_id
		-- 		INNER JOIN 'users' c ON b.user_id = c.id
		-- 		WHERE b.parent_comment_id IS NULL
		-- 			AND b.post_id = ?
		-- 		GROUP BY b.id
		-- 		ORDER BY COUNT(*) DESC;
		-- 	]],
		-- 	self.params.post_id)
		print("Found " .. #self.comments .. " comments")

		-- local post_data = db.select("* FROM 'posts' WHERE id = ?", self.params.post_id)
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

		-- lookup user_name from user_id
		-- local user_name = db.select("user_name FROM 'users' WHERE id=?")
		local u = Users:find(post_data["user_id"])
		print("User_name is " .. u['user_name'])
		self.user_name = u['user_name']

	end,

	GET = function(self)
		return { render = "post" }
	end,
}

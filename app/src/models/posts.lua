--- Posts model
-- @module models.posts

local model = require("lapis.db.model")
local Model, enum = model.Model, model.enum

local Posts = Model:extend("posts", {
	timestamp = true,

	-- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for/passing-an-object-to-url-for
	url_params = function(self, req, ...)
		-- local res = db.find(self.id)

		local subreddit_id = ''
		local post_id = ''
		local post_stub = ''

		local url = "/r/" .. subreddit_id .. "/comments/" .. post_id .. "/" .. post_stub
		return url, ...
	end,

	relations = {
		{ "comments", has_many = "Comments" },
		{ "subreddit", belongs_to = "Forum" }, -- has_one()?
		{ "user", belongs_to = "Users" },
		{ "votes", has_many = "Votes" },

		-- { "votes",
		--     has_many="Votes",
		--     where = {sub_id = id},
		--     order = "id desc",
		--     key = "post_id"
		-- },

		-- { "top_posts",
		--     has_many = "Posts",
		--     where = {sub_id = id},
		--     order = "id desc",
		--     key = "author"
		-- },
	},
})

Posts.statuses = enum({
	pending = 1,
	public = 2,
	private = 3,
	locked = 4,
	deleted = 5,
})

--- Get posts in a thread
-- @tparam number post_id Post ID
-- @tparam number offset Offset
-- @tparam number limit Limit
-- @treturn table posts
-- function Posts:get_top_level_comments(post_id, offset, limit)
-- 	local post = self:find(post_id)
-- 	return post:get_comments(offset, limit)
-- end

--- Get Post's karma score
-- function Posts:get_score(post_id, subreddit)
-- 	-- check subreddit is not nil
-- 	if subreddit == nil or subreddit == "" then
-- 		return false, "Invalid subreddit for post_id: " .. post_id
-- 	end

-- 	local votes_table = subreddit .. "_votes"
-- 	-- select count(upvote) from ? where ? is null
-- 	local ups = db.select(
-- 		"SELECT count(*) FROM ? WHERE post_id = ? AND WHERE ? is not null",
-- 		votes_table,
-- 		post_id,
-- 		user_id,
-- 		upvote
-- 	)
-- 	local downs =
-- 		db.select("SELECT count(*) FROM ? WHERE post_id = ? AND WHERE ? is null", votes_table, post_id, user_id, upvote)

-- 	if not ups or downs then
-- 		return false, "FIXME: getting score failed!"
-- 	end

-- 	print(string.format("Post %s in %s has %s upvotes, %s downs.", post_id, subreddit, #ups, #downs))

-- 	return ups - downs
-- end

return Posts

--- Posts model
-- @module models.posts

local model = require("lapis.db.model")
local Model, enum = model.Model, model.enum

local Posts = Model:extend("posts", {
	timestamp = true,

	-- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for/passing-an-object-to-url-for
	-- Build the args for url_for("post", ...) so `url_for(post)` resolves to
	-- /r/<subreddit>/comments/<id>/<title-stub>.
	url_params = function(self, req, ...)
		local Forum = require("src.models.forum")
		local sub = self.sub_id and Forum:find(self.sub_id)

		local stub = (self.title or ""):lower()
		stub = stub:gsub("[^%w]+", "_")
		stub = stub:gsub("^_+", "")
		stub = stub:gsub("_+$", "")

		return "post", {
			subreddit = sub and sub.name or "all",
			post_id = self.id,
			title_stub = stub ~= "" and stub or nil,
		}, ...
	end,

	relations = {
		{ "comments", has_many = "Comments" },
		-- The FK column is `sub_id`, not the default `subreddit_id`, so
		-- get_subreddit() needs an explicit key or it always resolves to nil.
		{ "subreddit", belongs_to = "Forum", key = "sub_id" },
		{ "user", belongs_to = "Users" },
		{ "votes", has_many = "Votes" },

		-- { "votes",
		--     has_many="Votes",
		--     where = {sub_id = id},
		--     order = "id desc",
		--     key = "post_id"
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

return Posts

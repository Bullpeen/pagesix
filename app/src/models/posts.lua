--- Posts model
-- @module models.posts

local db     = require "lapis.db"
-- local types  = schema.types
-- local util   = require("lapis.util")

local id = 99

local Model     = require("lapis.db.model").Model
local Posts     = Model:extend(id .. "_posts", {
	relations = {
		{ "subreddit",  belongs_to="Subreddits" },
		-- { "post",    belongs_to="Posts" },
		{ "comments",   has_many="Comments" },
		{ "votes",      has_many="Votes" },
		{ "user",       belongs_to = "Users" }
	}
})

print("RUNNING MODELS.POSTS")

--- Count comments in a post
-- @tparam integer post_id Post ID
-- @treturn integer posts
function Posts:count_comments(post_id)
	local post = self:find(post_id)
	return post:count("comments")
end

--- Get posts in a thread
-- @tparam number post_id Post ID
-- @tparam number offset Offset
-- @tparam number limit Limit
-- @treturn table posts
function Posts:get_top_level_comments(post_id, offset, limit)
	local post = self:find(post_id)
	return post:get_comments(offset, limit)
end

--- Get Post's karma score
function Posts:get_score(post_id, subreddit)
	-- check subreddit is not nil
	if subreddit == nil or subreddit == "" then
		return false, "Invalid subreddit for post_id: " .. post_id
	end

	local votes_table = subreddit .. "_votes"
	-- select count(upvote) from ? where ? is null
	local ups = db.select("SELECT count(*) FROM ? WHERE post_id = ? AND WHERE ? is not null", votes_table, post_id, user_id, upvote)
	local downs = db.select("SELECT count(*) FROM ? WHERE post_id = ? AND WHERE ? is null", votes_table, post_id, user_id, upvote)

	if not ups or downs then
		return false, "FIXME: getting score failed!"
	end

	print(string.format("Post %s in %s has %s upvotes, %s downs.", post_id, subreddit, #ups, #downs))

	return ups - downs
end

--- Check if Post is locked
function Posts:is_locked(post_id)
	local post = self:find(post_id)
	return post.locked
end

--- Check if Post is stickied
function Posts:is_stickied(post_id)
	local post = self:find(post_id)
	return post.stickied
end

--- Check if Post is NSFW
function Posts:is_nsfw(post_id)
	local post = self:find(post_id)
	return post.over_18
end

--- Check if Post is a self post (no url, contains body text)
function Posts:is_self(post_id)
	local post = self:find(post_id)
	return post.is_self
end

--- Given a table of post parameters, generate a permalink
-- @tparam table params Post parameters {post_id, user_id, title, url}
-- @treturn string permalink
function Posts:generate_permalink(params)
	-- TODO:

	local subreddit_name = get Subreddit:subreddit_name(params.post_id)
	local title_slug = utils.slugify(params.title)
	local post_id =  md5(title_slug .. params.user_id .. params.created_utc)

	return "/r/" .. subreddit_name .. "/comments/" .. params.post_id .. "/" .. title_slug
end

return Posts

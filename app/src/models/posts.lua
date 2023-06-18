--- Posts model
-- @module models.posts

local db     = require "lapis.db"
-- local types  = schema.types
-- local util   = require("lapis.util")

local Model     = require("lapis.db.model").Model
local Posts     = Model:extend("posts", {
	relations = {
		{ "subreddit",  belongs_to="Subreddits" },
		-- { "post",    belongs_to="Posts" },
		{ "comments",   has_many="Comments" },
		{ "votes",      has_many="Votes" },
		{ "user",       belongs_to = "Users" }
	}
})

--- Create a new post
-- @tparam table params Post parameters
-- @tparam table post post data
-- @tparam boolean op OP flag
-- @treturn boolean success
-- @treturn string error
-- function Posts:new(params, post, op)

-- 	-- normalize url
-- 	if params.url then
-- 		params.url = util.normalize_url(params.url)
-- 	end

-- 	-- TODO: url not posted to sub in last N days(?)

-- 	-- TODO: title max length

-- 	local post_table = post .. "_posts"

-- 	local res, err = db.insert(post_table, {
-- 		user_id = params.user_id,
-- 		permalink = params.permalink,
-- 		title = params.title,
-- 		url = params.url,
-- 		locked = params.locked,
-- 		created_utc = params.created_utc,
-- 		is_self = params.is_self,
-- 		over_18 = params.over_18,
-- 		body = params.body
-- 	})

-- 	if not res then
-- 		return false, "FIXME: creating a post failed! " .. err
-- 	end
-- end

--- Modify an existing post
-- @tparam table params Post parameters
-- @tparam string post_id Post ID
-- @treturn boolean success
-- function Posts:modify(params, post_id)
-- 	-- get subreddit from post_id
-- 	local subreddit = db.select("subreddit_id FROM posts WHERE id = ?", post_id)
-- 	local post_table = subreddit .. "_posts"

-- 	return db.update(post_table, {
-- 		edited = true,
-- 		permalink = params.permalink,
-- 		title = params.title,
-- 		url = params.url,
-- 		locked = params.locked,
-- 		over_18 = params.over_18,
-- 		body = params.body,
-- 	})
-- end

--- Delete post data
-- @tparam integer subreddit_id Subreddit ID
-- @tparam integer post_id Post ID
-- @treturn boolean success
-- @treturn string error
-- function Posts:delete(subreddit_id, post_id)
-- 	local post = Posts:find(subreddit_id, post_id)
-- 	return post:delete()
-- end

--- Get post data
-- @tparam number subreddit_id Subreddit ID
-- @tparam number post_id Local Post ID
-- @treturn table post
-- function Posts:get(subreddit_id, post_id)
-- 	local post = self:find {
-- 		subreddit_id = subreddit_id,
-- 		post_id  = post_id
-- 	}
-- 	return post and post or false, "FIXME"
-- end

--- Get post data
-- @tparam number id Post ID
-- @treturn table post
-- function Posts:get_post_by_id(id)
-- 	local post = self:find(id)
-- 	return post and post or false, "FIXME"
-- end

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

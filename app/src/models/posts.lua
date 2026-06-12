--- Posts model
-- @module models.posts

local model = require("lapis.db.model")
local db = require("lapis.db")
local Model, enum = model.Model, model.enum

local Posts = Model:extend("posts", {
	timestamp = true,

	constraints = {
		-- Lapis validates the title on create/update; truthy return blocks it.
		title = function(self, value)
			if not value or value == "" then
				return "Title is required"
			end
			if #value > 300 then
				return "Title must be under 300 characters"
			end
		end,
	},

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

--- Listing rows for a frontpage / subreddit, with the vote and comment
-- aggregates the templates and the Sort util expect.
--
-- This replaces the dependency on the pre-seeded v_hot_* SQL views: it works
-- on a freshly-migrated database, includes posts with zero votes, and is not
-- tied to any single sort order (callers pass the rows through Sort:sort).
-- @tparam[opt] number|table filters a subreddit id (legacy), or a table of
--   { sub_id = ..., user_id = ... } to restrict the listing
-- @treturn table array of plain post rows
function Posts:get_listing(filters)
	-- Backwards compatible: a bare number means sub_id.
	if type(filters) == "number" then
		filters = { sub_id = filters }
	end
	filters = filters or {}

	local query = [[
		a.id, a.title, a.url, a.body, a.is_self, a.over_18, a.locked, a.sub_id,
			a.created_at AS age, a.created_at,
			c.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 0) AS downvotes,
			(SELECT COUNT(*) FROM comments d WHERE d.post_id = a.id) AS num_comments
		FROM posts a
		INNER JOIN users c ON a.user_id = c.id
		INNER JOIN forum s ON a.sub_id = s.id
		WHERE a.locked = 0 AND a.deleted = 0]]

	if filters.sub_id then
		query = query .. " AND a.sub_id = " .. tonumber(filters.sub_id)
	end
	if filters.user_id then
		query = query .. " AND a.user_id = " .. tonumber(filters.user_id)
	end
	if filters.since then
		query = query .. " AND a.created_at >= " .. db.escape_literal(filters.since)
	end
	if filters.exclude_hidden_for then
		query = query .. " AND a.id NOT IN (SELECT post_id FROM hidden_posts WHERE user_id = "
			.. tonumber(filters.exclude_hidden_for) .. ")"
	end
	if filters.saved_for then
		query = query .. " AND a.id IN (SELECT post_id FROM saved_posts WHERE user_id = "
			.. tonumber(filters.saved_for) .. ")"
	end
	query = query .. " ORDER BY a.created_at DESC"

	local rows = db.select(query)

	for _, post in ipairs(rows) do
		post.permalink = "/r/" .. post.subreddit .. "/comments/" .. post.id
		post.domain = post.url and post.url:match("^%w+://([^/]+)") or ""
	end

	return rows
end

--- Full-text search over post titles/bodies via the FTS5 index (migration [7]),
-- ordered by relevance. Returns the same enriched rows as get_listing.
-- @tparam string query the user's search text
-- @treturn table array of post rows
function Posts:search(query)
	if not query or query == "" then
		return {}
	end
	-- Wrap as a quoted FTS5 phrase so arbitrary user input can't break the
	-- MATCH syntax (double-quotes are escaped by doubling).
	local phrase = '"' .. tostring(query):gsub('"', '""') .. '"'

	local rows = db.select([[
		a.id, a.title, a.url, a.body, a.is_self, a.over_18, a.locked, a.sub_id,
			a.created_at AS age, a.created_at,
			c.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 0) AS downvotes,
			(SELECT COUNT(*) FROM comments d WHERE d.post_id = a.id) AS num_comments
		FROM posts_fts f
		INNER JOIN posts a ON a.id = f.rowid
		INNER JOIN users c ON a.user_id = c.id
		INNER JOIN forum s ON a.sub_id = s.id
		WHERE posts_fts MATCH ? AND a.deleted = 0
		ORDER BY rank
		LIMIT 50]], phrase)

	for _, post in ipairs(rows) do
		post.permalink = "/r/" .. post.subreddit .. "/comments/" .. post.id
		post.domain = post.url and post.url:match("^%w+://([^/]+)") or ""
	end

	return rows
end

return Posts

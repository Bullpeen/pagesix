--- Comments model
-- @module models.comments

local Model = require("lapis.db.model").Model
local db = require("lapis.db")
local render_markdown = require("src.utils.markdown")

local Comments = Model:extend("comments", {
	timestamp = true,
	constraints = {
		-- Lapis calls this with the `body` column value on create/update; a
		-- truthy return blocks the write and is returned as the error.
		body = function(self, value)
			if not value or value == "" then
				return "Comment cannot be empty"
			end
			if #value > 4096 then
				return "Comment must be less than 4096 characters"
			end
		end,
	},
	relations = {
		-- A comment belongs to the user who wrote it (comments.user_id -> users.id).
		-- This was previously `has_one`, which looked for a non-existent
		-- comments.id reference on users and returned nil.
		{ "user", belongs_to = "Users" },
		{ "votes", has_many = "Votes" },
		-- { "parent_comment", belongs_to="Comments" },
		{ "post", belongs_to = "Posts" },
		-- NOTE: comments has no `subreddit_id` column, so `get_subreddit()`
		-- can't resolve. Reach the subreddit via the post instead
		-- (comment:get_post():get_subreddit()).
		-- { "subreddit", belongs_to = "Forum" },
	},
})

-- Finalize raw comment rows for rendering: vote score, permalink, and the
-- Markdown/[deleted] body. Shared by thread/permalink/by_user so they stay in
-- sync. Deleted comments are kept (so replies aren't orphaned) but blanked.
local function enrich(rows)
	for _, c in ipairs(rows) do
		c.score = tonumber(c.upvotes) - tonumber(c.downvotes)
		c.permalink = "/r/" .. c.subreddit .. "/comments/" .. c.post_id .. "/_/" .. c.id
		if tonumber(c.deleted) == 1 then
			c.author = "[deleted]"
			c.body_html = "[deleted]"
		else
			c.body_html = render_markdown(c.body)
		end
	end
	return rows
end

-- A single comment row shaped like a thread row (author, subreddit, vote
-- aggregates) but without depth/path, or nil. Used to pull in ancestor rows.
local function fetch_one(comment_id)
	local rows = db.query([[
		SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, c.edited,
			c.deleted, c.parent_comment_id, c.is_submitter,
			u.user_name AS author, s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = c.id AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = c.id AND v.upvote = 0) AS downvotes
		FROM comments c
		JOIN users u ON c.user_id = u.id
		JOIN posts p ON c.post_id = p.id
		JOIN forum s ON p.sub_id = s.id
		WHERE c.id = ]] .. tonumber(comment_id))
	return rows[1]
end

-- The focused comment plus all of its descendants, depth-ordered (the focused
-- comment is depth 0). A recursive CTE walks the parent->child links and builds
-- a zero-padded `path` so children sort directly under their parent.
local function subtree(comment_id)
	return db.query([[
		WITH RECURSIVE sub AS (
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, c.edited,
				c.deleted, c.parent_comment_id, c.is_submitter,
				0 AS depth, printf('%020d', c.id) AS path
			FROM comments c
			WHERE c.id = ]] .. tonumber(comment_id) .. [[
			UNION ALL
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, c.edited,
				c.deleted, c.parent_comment_id, c.is_submitter,
				t.depth + 1, t.path || '.' || printf('%020d', c.id)
			FROM comments c
			JOIN sub t ON c.parent_comment_id = t.id
		)
		SELECT t.id, t.post_id, t.user_id, t.body, t.created_at, t.edited,
			t.deleted, t.parent_comment_id, t.is_submitter, t.depth,
			u.user_name AS author, s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = t.id AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = t.id AND v.upvote = 0) AS downvotes
		FROM sub t
		JOIN users u ON t.user_id = u.id
		JOIN posts p ON t.post_id = p.id
		JOIN forum s ON p.sub_id = s.id
		ORDER BY t.path
	]])
end

--- The full comment thread for a post, ordered depth-first with a `depth`
-- level for indentation. A SQLite recursive CTE walks the parent -> child
-- links, building a zero-padded materialized `path` so children always sort
-- directly under their parent. Each row also carries the author name and vote
-- aggregates, ready for rendering.
-- @tparam number post_id
-- @treturn table array of comment rows (id, body, author, score, depth, ...)
function Comments:thread(post_id)
	local rows = db.query([[
		WITH RECURSIVE thread AS (
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, c.edited,
				c.deleted, c.parent_comment_id, c.is_submitter,
				0 AS depth,
				printf('%020d', c.id) AS path
			FROM comments c
			WHERE c.post_id = ]] .. tonumber(post_id) .. [[
				AND c.parent_comment_id IS NULL
				AND c.approved = 1
			UNION ALL
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, c.edited,
				c.deleted, c.parent_comment_id, c.is_submitter,
				t.depth + 1,
				t.path || '.' || printf('%020d', c.id)
			FROM comments c
			JOIN thread t ON c.parent_comment_id = t.id
			WHERE c.approved = 1
		)
		SELECT t.id, t.post_id, t.user_id, t.body, t.created_at, t.edited,
			t.deleted, t.parent_comment_id, t.is_submitter, t.depth,
			u.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = t.id AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = t.id AND v.upvote = 0) AS downvotes
		FROM thread t
		JOIN users u ON t.user_id = u.id
		JOIN posts p ON t.post_id = p.id
		JOIN forum s ON p.sub_id = s.id
		ORDER BY t.path
	]])

	return enrich(rows)
end

--- A user's recent comments (flat, newest first) with the same fields the
-- comments fragment renders. depth is 0 since these aren't shown as a tree.
-- @tparam number user_id
-- @treturn table array of comment rows
function Comments:by_user(user_id)
	local rows = db.select([[
		a.id, a.post_id, a.user_id, a.body, a.created_at, a.deleted,
			a.parent_comment_id, a.is_submitter, 0 AS depth,
			u.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = a.id AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = a.id AND v.upvote = 0) AS downvotes
		FROM comments a
		INNER JOIN users u ON a.user_id = u.id
		INNER JOIN posts p ON a.post_id = p.id
		INNER JOIN forum s ON p.sub_id = s.id
		WHERE a.user_id = ]] .. tonumber(user_id) .. [[ AND a.deleted = 0 AND a.approved = 1
		ORDER BY a.created_at DESC]])

	return enrich(rows)
end

--- Comments in a subreddit awaiting moderator approval (the queue), newest
-- first. Joined to their post so the queue can link back.
-- @tparam number sub_id
-- @treturn table array of comment rows
function Comments:pending_for_sub(sub_id)
	return db.select(
		[[
		a.id, a.post_id, a.body, a.created_at, u.user_name AS author,
			p.title AS post_title, s.name AS subreddit
			FROM comments a
			INNER JOIN users u ON a.user_id = u.id
			INNER JOIN posts p ON a.post_id = p.id
			INNER JOIN forum s ON p.sub_id = s.id
			WHERE p.sub_id = ? AND a.approved = 0 AND a.deleted = 0
			ORDER BY a.created_at DESC]],
		tonumber(sub_id)
	)
end

--- A single comment's permalink view: the focused comment plus its full reply
-- subtree, optionally preceded by up to `context` ancestor comments (a linear
-- chain above it, for context). Depth-ordered like `thread`, so the existing
-- comments fragment renders it with the right indentation.
-- @tparam number comment_id the focused comment
-- @tparam[opt=0] number context how many ancestor levels to include above it
-- @treturn table array of comment rows (empty if the comment is unknown)
function Comments:permalink_thread(comment_id, context)
	comment_id = tonumber(comment_id)
	if not comment_id then
		return {}
	end
	context = math.max(0, math.floor(tonumber(context) or 0))

	local focused = self:find(comment_id)
	if not focused then
		return {}
	end

	-- Walk up to `context` ancestors, collecting them topmost-first.
	local ancestors = {}
	local pid = focused.parent_comment_id
	while pid and #ancestors < context do
		local parent = fetch_one(pid)
		if not parent then
			break
		end
		table.insert(ancestors, 1, parent)
		pid = parent.parent_comment_id
	end

	-- Ancestors form the linear chain above (depths 0..k-1); the focused
	-- comment and its descendants follow, shifted down by that chain's length.
	local rows = {}
	for depth, a in ipairs(ancestors) do
		a.depth = depth - 1
		rows[#rows + 1] = a
	end
	local base = #ancestors
	for _, c in ipairs(subtree(comment_id)) do
		c.depth = tonumber(c.depth) + base
		rows[#rows + 1] = c
	end

	return enrich(rows)
end

return Comments

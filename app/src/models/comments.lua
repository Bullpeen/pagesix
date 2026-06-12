--- Comments model
-- @module models.comments

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

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
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at,
				c.parent_comment_id, c.is_submitter,
				0 AS depth,
				printf('%020d', c.id) AS path
			FROM comments c
			WHERE c.post_id = ]] .. tonumber(post_id) .. [[
				AND c.parent_comment_id IS NULL
				AND c.deleted = 0
			UNION ALL
			SELECT c.id, c.post_id, c.user_id, c.body, c.created_at,
				c.parent_comment_id, c.is_submitter,
				t.depth + 1,
				t.path || '.' || printf('%020d', c.id)
			FROM comments c
			JOIN thread t ON c.parent_comment_id = t.id
			WHERE c.deleted = 0
		)
		SELECT t.id, t.post_id, t.user_id, t.body, t.created_at,
			t.parent_comment_id, t.is_submitter, t.depth,
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

	for _, c in ipairs(rows) do
		c.score = tonumber(c.upvotes) - tonumber(c.downvotes)
		c.permalink = "/r/" .. c.subreddit .. "/comments/" .. c.post_id .. "/_/" .. c.id
	end

	return rows
end

return Comments

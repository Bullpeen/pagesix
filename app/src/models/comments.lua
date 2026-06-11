--- Comments model
-- @module models.comments

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Comments = Model:extend("comments", {
	timestamp = true,
	constraints = {
		--- Apply constraints when updating/adding a Comment, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		name = function(self, value)
			if value then
				if string.len(value.body) > 4096 then
					return "Comment must be less than 4096 characters"
				end
				if value.body == nil or value.body == "" then
					return "Comment cannot be empty"
				end
			-- else
			-- 	print("NOPE")
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

--- Comments for a post, with author name, vote aggregates, and a permalink,
-- ready for rendering. Like Posts:get_listing but for comments.
-- @tparam number post_id
-- @treturn table array of comment rows
function Comments:listing(post_id)
	local rows = db.select([[
		a.id, a.post_id, a.user_id, a.body, a.created_at, a.parent_comment_id,
			u.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = a.id AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.comment_id = a.id AND v.upvote = 0) AS downvotes
		FROM comments a
		INNER JOIN users u ON a.user_id = u.id
		INNER JOIN posts p ON a.post_id = p.id
		INNER JOIN forum s ON p.sub_id = s.id
		WHERE a.post_id = ]] .. tonumber(post_id) .. [[ AND a.deleted = 0
		ORDER BY a.created_at ASC]])

	for _, c in ipairs(rows) do
		c.score = tonumber(c.upvotes) - tonumber(c.downvotes)
		c.permalink = "/r/" .. c.subreddit .. "/comments/" .. c.post_id .. "/_/" .. c.id
	end

	return rows
end

return Comments

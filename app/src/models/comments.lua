--- Comments model
-- @module models.comments

local Model = require("lapis.db.model").Model

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
		{ "user", has_one = "Users" },
		{ "votes", has_many = "Votes" },
		{ "post", belongs_to = "Posts" },
		-- { "parent_comment", belongs_to="Comments" },
		{ "subreddit", belongs_to = "Subreddits" },
	},
})

--- Get comments karma score
-- @tparam string post_id
-- @treturn number score
function Comments:get_score(post_id)
	-- TODO:

	-- get board_id
	-- check board_id_votes table
	-- count upvotes and total rows
	-- downvotes = total - upvotes
	-- return upvotes - downvotes
end

--- Check if comment is stickied to the Post
-- @tparam string comment_id
-- @treturn boolean stickied
function Comments:is_stickied(comment_id)
	local comment = self:find(comment_id)
	return comment.stickied
end

return Comments

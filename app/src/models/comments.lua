--- Comments model
-- @module models.comments

local db       = require "lapis.db"

local Model    = require("lapis.db.model").Model
local Comments = Model:extend("comments", {
	constraints = {
		--- Apply constraints when updating/adding a Comment, returns truthy to indicate error
		-- @tparam table self
        -- @tparam table value User data
		-- @treturn string error
		name = function(self, value)

            if string.len(value.body) > 4096 then
                return "Comment must be less than 4096 characters"
            end
            if value.body == nil or value.body == "" then
                return "Comment cannot be empty"
            end
        end
    },
    relations = {
		{ "user",           has_one="Users" },
        { "votes",          has_many="Votes" },
        { "post",           belongs_to="Posts" },
        -- { "parent_comment", belongs_to="Comments" },
        { "subreddit",      belongs_to="Subreddits"}
    }
})

--- Add a new comment
-- @tparam string params
-- @treturn boolean success
function Comments:new(params)
    -- lookup
	local comments_table = params.subreddit .. "_comments"

	db.insert(comments_table, {
		post_id = params.post_id,
        parent_comment_id = params.parent_comment_id,
        body = params.body,
        created_utc = params.created_utc,
        is_submitter = params.is_submitter,
        stickied = params.stickied,
	})
end

--- Edit a comment
-- @tparam table params
-- @treturn table result
function Comments:modify(params)
    local comments_table = params.board .. "_comments"

	local res = db.update(comments_table, {
		edited = true,
        body = params.body,
        stickied = params.stickied,
	})

    return res
end

--- Delete a comment
-- @tparam string subreddit_id
-- @tparam string comment_id
-- @treturn boolean success
function Comments:delete(subreddit_id, comment_id)
    -- TODO:

    -- check if authorized?
    local comment = Comments:find(comment_id)
    return comment:delete()
end

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

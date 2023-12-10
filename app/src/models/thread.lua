--- Thread model
-- @module models.thread

local db     = require "lapis.db"

local Model     = require("lapis.db.model").Model
local Thread    = Model:extend("comments")

-- comment_id, parent_comment_id, post_id

print("RUNNING MODELS.Thread")

--- Get a thread
-- @tparam string post_id
-- @tparam string comment_id
-- @tparam string parent_comment_id
-- @treturn table thread
function Thread:get(post_id, comment_id, parent_comment_id)
    -- TODO:

    -- parse subreddit_name from post_id

    -- get comment
    if params.parent_comment_id ~= nil then
        Comments:get_comment(params.parent_comment_id)
    end

    if params.post_id ~= nil then
        get_post(params.post_id)
    end

    local cmthrd = {
        comment_id = params.comment_id,
        parent_comment_id = params.parent_comment_id,
        post_id = params.post_id,
    }
    return cmthrd and cmthrd or false, "FIXME: listing threads failed"
end

--- Thread model
-- @module models.thread

-- local db = require("lapis.db")

local Model = require("lapis.db.model").Model
local Thread = Model:extend("comments")
-- local Post = Model:extend("posts")

-- comment_id, parent_comment_id, post_id

return Thread

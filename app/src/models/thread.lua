--- Thread model
-- @module models.thread

local Model = require("lapis.db.model").Model
local Thread = Model:extend("comments")

-- comment_id, parent_comment_id, post_id

return Thread

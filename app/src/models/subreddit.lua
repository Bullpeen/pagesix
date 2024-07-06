--- Subreddit model
-- @module models.subreddit

local Model = require("lapis.db.model").Model
local Forum = require("models.forum")

-- TODO for enum of subreddits?
-- for name in Forum.object_types do
-- end

-- -- local name = name or "frontpage"
-- local Subreddit = Model:extend("v_hot_" .. name, {
--     timestamp = true,

--     -- TODO
--     -- url_params = function(self, req, ...)
--     -- 	return "subreddit", { id = self.id }, ...
--     -- end,

--     constraints = {
--         --- Apply constraints
--         -- @tparam table self
--         -- @tparam table value User data
--         -- @treturn string error
--         title = function(self, value)
--             -- title is maximum 256 characters
--             if string.len(value) > 256 then
--                 return "Title is too long"
--             end

--             -- title is minimum 2 characters
--             if string.len(value) < 1 then
--                 return "Title is too short"
--             end
--         end,

--         url = function(self, value)
--             -- local uri, err = Silva:new(value)

--             -- if not uri then
--             --     return("invalid URL: " .. err)
--             -- end
--         end,

--         body = function(self, value)
--             if self.is_self and string.len(value) > 0 then
--                 return "Only self posts can have body text"
--             end

--             -- body text is maximum 16kb
--             if string.len(value) > 16384 then
--                 return "Body text is too long"
--             end
--         end,
--     },

--     relations = {
--         { "creator",   belongs_to = "Users" },
--         { "subreddit", has_one    = "Forum" },
--         { "post",      has_many   = "Posts" },

--         -- { "top_posts",
-- 		--     has_many = "Posts",
-- 		--     where = {sub_id = id},
-- 		--     order = "id desc",
-- 		--     key = "author"
-- 		-- },

--     },
-- })

-- return Subreddit
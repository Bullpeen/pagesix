--- Subreddit action
-- @module action.subreddit

local Forum = require("src.models.forum")
local Sort = require("src.utils.sort")
local db = require("lapis.db")

return {
    before = function(self)
        -- self.params.sort

        local subreddit_name = self.params.subreddit
        local sort = self.params.sort or "hot"

        -- convert subreddit_id to name
        local subreddit_id = Forum.object_types:for_db(subreddit_name)

        local sub = Forum:find(subreddit_id)
        self.posts = Sort:sort(sub:get_frontpage(sub.name), sort)

        -- self.bob = db:select("* FROM ?", "v_forum")
    end,

    -- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
    on_error = function(self)
        return { render = "subreddit" }
    end,

    GET = function(self)
        return { render = "subreddit" }
    end,
}

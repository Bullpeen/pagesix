--- Comment action
-- @module action.comment

local db = require("lapis.db")

local Comments = require("models.comments")
local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Subreddit = require("models.subreddit")
local Users = require("models.users")
local Votes = require("src.models.votes")


return {
    before = function(self)
        -- self.params.subreddit
        -- self.params.post_id
        -- self.params.title_stub
        -- self.params.comment_id
        -- ? self.params.q

        -- Check if subreddit is nil or empty
        local sub_name = self.params.subreddit or 'ask'
        if sub_name == nil or sub_name == "" then
            print("Subreddit is unknown: " .. sub_name)
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        -- Get subreddit from sub_name
        -- local sub = Subreddit:find({name = sub_name})

        -- TODO return table like, sorted by highest score (upvotes - downvotes)
        -- {
        -- 		comment_id: { body, user_id, created_at, edited, upvotes, downvotes, (parent_id) },
        --		comment_id: { ... },
        -- }

        local comment = Comments:find(self.params.comment_id)
        if not comment then
            return self:write({ redirect_to = self:url_for("homepage") })
        end
        -- The view iterates self.comments, so wrap the single comment in a list.
        self.comments = { comment }

        -- TODO: walk up `context` (grand)parent comments from the ?q=...N param.
        -- The previous implementation called Posts:get_comment() (which does not
        -- exist), indexed self.comment (a typo for self.comments), and compared a
        -- string to a number -- so it always errored. Disabled until parent
        -- threading is implemented properly.
        -- local context = self.params.q and tonumber(string.match(self.params.q, "%d+$"))

        local post_data = Posts:find(self.params.post_id or 1)
        if post_data then
            -- posts has no user_name column; resolve the author via the relation.
            local author = post_data:get_user()
            self.user_name = author and author.user_name
            self.title = post_data["title"]
            self.url = post_data["url"]
            -- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for
            -- self.permalink = self:url_for(self.params.comment_id)
            self.created_at = post_data["created_at"]
        end
    end,

    GET = function(self)
        return { render = "comment" }
    end,
}

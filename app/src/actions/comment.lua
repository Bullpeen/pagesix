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

        self.comments = Comments:find(self.params.comment_id)

        -- self.comments = Comments:find({parent_comment_id = self.params.comment_id})
        print("Found " .. #self.comments .. " comments")

        local context

        -- TODO check context=N from url param, return that many (grand)parents in self.comments
        if self.params.q then
            context = string.match(self.params.q, "%d+$")
        end

        -- TODO recursively include # of comments from the self.params.q argument

        if context ~= nil and context > 1 then
            -- loop context times and fetch each parent comments
            for i = 1, context do
                -- if comment has a parent, fetch it
                if self.comments[i] and self.comments[i].parent_comment_id then -- ~= nil
                    print("Looking up parent comment: " .. self.comments[i].parent_comment_id)
                    local p = Posts:get_comment({ parent_comment_id = self.comment[i].parent_comment_id })
                    table.insert(self.comments, p[1])
                else
                    break
                end
            end
        end


        local post_data = Posts:find(self.params.post_id or 1)
        -- print("Post data:")
        -- require("pl.pretty").dump(post_data)

        -- pass data to template
        self.user_name = post_data["user_name"]
        self.title = post_data["title"]
        self.url = post_data["url"]
        -- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for
        -- self.permalink = self:url_for(self.params.comment_id)
        self.created_at = post_data["created_at"]
    end,

    GET = function(self)
        return { render = "comment" }
    end,
}

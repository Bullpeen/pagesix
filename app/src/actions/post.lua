--- Post action
-- @module action.post

local Comments = require("models.comments")
local Forum = require("src.models.forum")
local Posts = require("src.models.posts")

return {
    before = function(self)
        -- self.params.subreddit
        -- self.params.post_id
        -- ? self.params.title_stub

        -- Check if subreddit is nil or empty
        local sub_name = self.params.subreddit
        if sub_name == nil or sub_name == "" then
            print("Subreddit is unknown: " .. sub_name)
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        -- print("Looking up " .. self.params.subreddit)
        local subreddit = Forum:find({ name = self.params.subreddit })
        -- require 'pl.pretty'.dump(subreddit)
        if subreddit == nil then
            print("Subreddit is unknown: " .. sub_name)
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        -- TODO paginate

        local post_data, err = Posts:find(self.params.post_id)
        if err then print("WHOOPS!" .. err) end
        if not post_data then
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        -- Full comment thread (depth-ordered, with author + vote aggregates).
        self.comments = Comments:thread(post_data.id)

        -- print("Post data:")
        -- require 'pl.pretty'.dump(post_data[1])

        self.subreddit = self.params.subreddit
        self.post_id = self.params.post_id
        self.title_stub = self.params.title_stub
        self.permalink = post_data["permalink"]
        self.created_at = post_data["created_at"]
        self.edited = tonumber(post_data["edited"]) == 1
        self.post_user_id = post_data["user_id"]
        self.removed = tonumber(post_data["locked"]) == 1
        self.can_moderate = self.current_user
            and Forum:can_moderate(self.current_user.id, subreddit)

        if tonumber(post_data["deleted"]) == 1 then
            -- Keep the page (and its comments) but blank the post itself.
            self.title = "[deleted]"
            self.user_name = "[deleted]"
            self.deleted = true
        else
            self.title = post_data["title"]
            self.url = post_data["url"]
            if tonumber(post_data["is_self"]) == 1 then
                self.is_self = true
                self.body_html = require("src.utils.markdown")(post_data["body"])
                self.body = post_data["body"]
            end
            local u = post_data:get_user()
            self.user_name = u["user_name"]
        end
    end,

    GET = function(self)
        return { render = "post" }
    end,
}

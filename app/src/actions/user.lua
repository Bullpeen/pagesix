--- User action
-- @module action.user

local Users = require("models.users")

return {
    before = function(self)
        -- self.params.user_name

        -- print("Looking up " .. self.params.user_name)
        local user = Users:find({ user_name = self.params.user_name })

        -- Unknown user: redirect home instead of crashing on a nil index.
        if not user then
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        self.user_name = user.user_name

        -- TODO paginate
        self.comments = user:get_comments()
        -- print("Number of comments: " .. #self.comments)

        -- TODO paginate
        self.posts = user:get_posts()
        -- print("Number of posts: " .. #self.posts)
    end,

    GET = function(self)
        return { render = "user" }
    end,
}

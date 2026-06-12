--- User action
-- @module action.user

local Users = require("models.users")
local Posts = require("src.models.posts")
local Comments = require("models.comments")

return {
    before = function(self)
        local user = Users:find({ user_name = self.params.user_name })

        -- Unknown user: redirect home instead of crashing on a nil index.
        if not user then
            return self:write({ redirect_to = self:url_for("homepage") })
        end

        self.user_name = user.user_name
        self.created_at = user.created_at
        self.karma = Users:karma(user.id)

        -- The posts/comments fragments expect rows with vote aggregates etc.,
        -- so use the same enriched queries the listing pages do (filtered to
        -- this user) rather than the raw relation rows.
        -- TODO paginate
        self.posts = Posts:get_listing({ user_id = user.id })
        self.comments = Comments:by_user(user.id)
    end,

    GET = function(self)
        return { render = "user" }
    end,
}

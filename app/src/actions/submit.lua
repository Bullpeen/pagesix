--- Submit action
-- @module action.submit

local Posts = require("src.models.posts")
local Forum = require("src.models.forum")
local Users = require("models.users")

return {
    before = function(self) end,

    GET = function(self)
        return { render = "submit" }
    end,

    -- Form fields (see views/fragments/form_submit.etlua): url, title, subreddit.
    POST = function(self)
        -- /submit is behind auth (src/auth.lua), so a user must be signed in.
        local user = self.session.current_user
            and Users:find({ user_name = self.session.current_user })
        if not user then
            return self:write({ redirect_to = self:url_for("login") })
        end

        -- Subreddits live in the `forum` table, keyed by name.
        local sub = self.params.subreddit
            and Forum:find({ name = self.params.subreddit })
        if not sub then
            self.errors = { "Unknown subreddit: " .. tostring(self.params.subreddit) }
            return { render = "submit" }
        end

        local post, err = Posts:create({
            user_id = user.id,
            sub_id = sub.id,
            title = self.params.title,
            url = self.params.url,
        })

        if not post then
            self.errors = { err }
            return { render = "submit" }
        end

        return { redirect_to = self:url_for(post) }
    end,
}

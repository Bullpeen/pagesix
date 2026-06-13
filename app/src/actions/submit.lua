--- Submit action
-- @module action.submit

local Posts = require("src.models.posts")
local Forum = require("src.models.forum")
local Users = require("models.users")
local Spam = require("src.utils.spam")

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

        -- A post is either a link (url) or a self/text post (body). If a body
        -- is given and no url, it's a self post.
        local url = self.params.url
        local body = self.params.body
        if (url == nil or url == "") and (body == nil or body == "") then
            self.errors = { "Provide a URL or some text" }
            return { render = "submit" }
        end
        local is_self = (url == nil or url == "") and body ~= nil and body ~= ""

        -- Bayesian spam check on the prose (title + self-post body; the URL is
        -- not tokenized as text). Fails open if untrained / too short.
        if Spam.is_spam((self.params.title or "") .. " " .. (body or "")) then
            self.errors = { "Your post looks like spam and was not submitted." }
            return { render = "submit" }
        end

        local post, err = Posts:create({
            user_id = user.id,
            sub_id = sub.id,
            title = self.params.title,
            url = (url ~= "") and url or nil,
            body = (body ~= "") and body or nil,
            is_self = is_self and 1 or 0,
        })

        if not post then
            self.errors = { err }
            return { render = "submit" }
        end

        return { redirect_to = self:url_for(post) }
    end,
}

--- Subscribed action
-- @module action.subscribed

local Forum = require("src.models.forum")
local Users = require("models.users")

return {
    before = function(self)
        if self.session.current_user ~= nil then
            print("Looking up " .. self.session.current_user)
            -- require 'pl.pretty'.dump(self.session)
            local user = Users:find({ user_name = self.session.current_user })

            if user then
                self.user_name = user.user_name
                self.subreddits = user:get_subscriptions()
                for _, s in pairs(self.subreddits) do
                    -- TODO sql-ize
                    s.name = Forum.object_types:to_name(s.subreddit_id)
                    -- s.description = ...
                    -- s.subscribers = ...
                end
            end
        else
            print("No session found")
        end
    end,

    GET = function(self)
        return { render = "subscribed" }
    end,
}

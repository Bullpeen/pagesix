--- Subscribe/unsubscribe (toggle) action
-- @module action.subscribe

local Users = require("models.users")
local Forum = require("src.models.forum")
local Subscriptions = require("models.subscriptions")

return {
	-- POST /subscribe/:subreddit  (toggles the current user's subscription)
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return { redirect_to = self:url_for("homepage") }
		end

		Subscriptions:toggle(user.id, sub.id)

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("subreddit", { subreddit = sub.name }) }
	end,
}

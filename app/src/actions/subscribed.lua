--- Subscribed action
-- @module action.subscribed

local Users = require("models.users")
local Subscriptions = require("models.subscriptions")

return {
	before = function(self)
		if self.session.current_user then
			local user = Users:find({ user_name = self.session.current_user })
			if user then
				self.user_name = user.user_name
				self.subreddits = Subscriptions:subscribed_forums(user.id)
			end
		end
	end,

	GET = function(self)
		return { render = "subscribed" }
	end,
}

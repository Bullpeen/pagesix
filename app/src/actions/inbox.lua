--- Inbox: reply notifications for the current user
-- @module action.inbox

local Users = require("models.users")
local Notifications = require("models.notifications")

return {
	-- GET /inbox
	before = function(self)
		if self.session.current_user then
			local user = Users:find({ user_name = self.session.current_user })
			if user then
				self.user_name = user.user_name
				self.notifications = Notifications:for_user(user.id)
				Notifications:mark_read(user.id)
			end
		end
	end,

	GET = function(self)
		return { render = "inbox" }
	end,
}

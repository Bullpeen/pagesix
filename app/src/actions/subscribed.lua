--- Subscribed action
-- @module action.subscribed

-- local db = require("lapis.db")
local Users = require("models.users")

return {
	before = function(self)
		if self.session.current_user ~= nil then
			print("Looking up " .. self.session.current_user)
			-- require 'pl.pretty'.dump(self.session)
			local user = Users:find({user_name = self.session.current_user})

			self.user_name = user.user_name
			self.subreddits = user:get_subscriptions()
		else
			print("No session found")
		end
	end,

	GET = function(self)
		return { render = "subscribed" }
	end,
}

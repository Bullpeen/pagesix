--- Register action
-- @module action.register

local Users = require("models.users")

return {
	before = function(self) end,

	GET = function(self)
		return { render = "register" }
	end,

	POST = function(self)
		-- Users model
		print(
			"self is "
				.. self.params.name
				.. ", "
				.. self.params.passwd
				.. ", "
				.. self.params.passwd2
				.. ", "
				.. self.params.email
		)
		if self.params.passwd == self.params.passwd2 then
			local user, err = Users:new(self.params, self.params.passwd)

			if not err then
				self.session.current_user = user.user_name
			else
				print("THERE WAS AN ERROR")
			end
		end
	end,
}

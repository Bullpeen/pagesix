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

		-- TODO make secure
		-- https://github.com/snap-cloud/snapCloud/blob/master/passwords.lua
		if self.params.passwd == self.params.passwd2 then
			local s, err = Users:create({
				user_name = self.params.name,
				user_email = self.params.email,
				user_pass = self.params.passwd,
			})
			if not err then
				self.session.current_user = s.user_name
			else
				print("error creating " .. self.params.name)
				print(err)
			end
		end
	end,
}

--- Login action
-- @module action.login

local Users = require("models.users")
local Password = require("src.utils.password")

-- The CSRF token is generated/validated globally in app.lua's before_filter
-- (it covers every state-changing form), so this action only handles auth.
return {
	before = function(self)
		if self.session.current_user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
	end,

	GET = function(self)
		return { render = "login" }
	end,

	POST = function(self)
		local user = self.params.username and Users:find({ user_name = self.params.username })
		if user and Password.verify(self.params.password, user.user_pass) then
			self.session.current_user = user.user_name
			return { redirect_to = self:url_for("homepage") }
		end

		self.form_error = "Invalid username or password."
		return { render = "login" }
	end,
}

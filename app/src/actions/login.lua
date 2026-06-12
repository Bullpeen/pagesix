--- Login action
-- @module action.login

local Users = require("models.users")
local Password = require("src.utils.password")
local csrf = require("lapis.csrf")

return {
	before = function(self)
		if self.session.current_user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
	end,

	GET = function(self)
		self.csrf_token = csrf.generate_token(self)
		return { render = "login" }
	end,

	POST = function(self)
		if not csrf.validate_token(self) then
			self.csrf_token = csrf.generate_token(self)
			self.error = "Invalid session. Please try again."
			return { render = "login" }
		end

		local user = self.params.username and Users:find({ user_name = self.params.username })
		if user and Password.verify(self.params.password, user.user_pass) then
			self.session.current_user = user.user_name
			return { redirect_to = self:url_for("homepage") }
		end

		self.csrf_token = csrf.generate_token(self)
		self.error = "Invalid username or password."
		return { render = "login" }
	end,
}

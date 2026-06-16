--- Password reset completion action (set a new password from a token)
-- @module action.password_reset

local Users = require("models.users")
local Password = require("src.utils.password")
local PasswordResets = require("models.password_resets")

-- CSRF is generated/validated globally in app.lua's before_filter.
return {
	before = function(self)
		if self.session.current_user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
		self.token = self.params.token
	end,

	GET = function(self)
		if not PasswordResets:valid(self.token) then
			self.invalid = true
		end
		return { render = "password_reset" }
	end,

	POST = function(self)
		local row = PasswordResets:valid(self.token)
		if not row then
			self.invalid = true
			return { render = "password_reset" }
		end

		local passwd = self.params.passwd or ""
		if passwd ~= (self.params.passwd2 or "") then
			self.form_error = "Passwords do not match."
			return { render = "password_reset" }
		end
		if #passwd < 7 then
			self.form_error = "Password must be at least 7 characters."
			return { render = "password_reset" }
		end

		local user = Users:find(tonumber(row.user_id))
		if not user then
			self.invalid = true
			return { render = "password_reset" }
		end

		user:update({ user_pass = Password.hash(passwd) })
		row:delete() -- one-shot: consume the token
		self.session.current_user = user.user_name
		return { redirect_to = self:url_for("homepage") }
	end,
}

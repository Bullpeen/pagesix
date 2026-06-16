--- Register action
-- @module action.register

local Users = require("models.users")
local Password = require("src.utils.password")

-- CSRF is generated/validated globally in app.lua's before_filter.
local function fail(self, message)
	self.form_error = message
	return { render = "register" }
end

return {
	before = function(self)
		if self.session.current_user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
	end,

	GET = function(self)
		return { render = "register" }
	end,

	POST = function(self)
		local passwd = self.params.passwd or ""
		if passwd ~= (self.params.passwd2 or "") then
			return fail(self, "Passwords do not match.")
		end
		-- Validate the plaintext length here: the model's user_pass constraint
		-- would only ever see the (always ~60 char) bcrypt hash.
		if #passwd < 7 then
			return fail(self, "Password must be at least 7 characters.")
		end
		if self.params.name and Users:find({ user_name = self.params.name }) then
			return fail(self, "That username is taken.")
		end

		-- The Users model constraints validate the username/email; create
		-- returns nil + the message on failure.
		local user, err = Users:create({
			user_name = self.params.name,
			user_email = self.params.email,
			user_pass = Password.hash(passwd),
		})
		if not user then
			return fail(self, err or "Could not create account.")
		end

		self.session.current_user = user.user_name
		return { redirect_to = self:url_for("homepage") }
	end,
}

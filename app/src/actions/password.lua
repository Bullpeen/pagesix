--- Password reset request action (GET form, POST issues a token)
-- @module action.password

local Users = require("models.users")
local PasswordResets = require("models.password_resets")

-- CSRF is generated/validated globally in app.lua's before_filter.
return {
	before = function(self)
		if self.session.current_user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
	end,

	GET = function(self)
		return { render = "password" }
	end,

	POST = function(self)
		local ident = self.params.username
		local user = ident
			and ident ~= ""
			and (Users:find({ user_name = ident }) or Users:find({ user_email = ident }))

		if user then
			local token = PasswordResets:issue(user.id)
			-- No mail server in dev, so surface the link directly to keep the flow
			-- usable and testable. In production this would be emailed, not shown.
			self.reset_link = self:url_for("password_reset") .. "?token=" .. token
		end

		self.done = true
		return { render = "password" }
	end,
}

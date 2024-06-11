--- Auth URLs
-- @module src.auth

local cached = require("lapis.cache").cached
local r2 = require("lapis.application").respond_to

local function auth(app)
	app:match("login", "/login", cached(r2(require("actions.login"))))
	app:match("password", "/password", cached(r2(require("actions.register"))))
	app:match("register", "/register", cached(r2(require("actions.register"))))

	app:match("logout", "/logout", function(self)
		-- Logout
		self.session.current_user = nil

		-- required(?) to force a write to the session, otherwise would be ignored
		-- https://github.com/leafo/lapis/issues/32
		self.session._dummy = true

		return { redirect_to = self:url_for("homepage") }
	end)

	return app
end

return auth

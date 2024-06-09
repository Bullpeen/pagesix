--- Auth URLs
-- @module src.auth

local r2    = require("lapis.application").respond_to

local function auth(app)
    app:match("password", "/password", r2(require "actions.register"))
    -- app:match("login",    "/login",    r2(require "actions.login"))
    app:match("login",    "/login",     r2(require "actions.login"))
    -- app:get("register",    "/register",  r2(require "actions.register"))
    -- app:post("register",    "/register", r2(require "actions.register"))

    app:match("logout",   "/logout",   function(self)
        -- Logout
        self.session.current_user  = nil
        self.session._dummy = true -- required to force a write to the session, otherwise would be ignored
        return { redirect_to = self:url_for("homepage") }
    end)

    return app
end

return auth

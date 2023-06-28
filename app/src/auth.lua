--- Auth URLs
-- @module src.auth

local r2    = require("lapis.application").respond_to

function auth(app)
    app:match("password", "/password", r2(require "actions.register"))
    -- app:match("login",    "/login",    r2(require "actions.login"))
    app:post("login",    "/login",     r2(require "actions.login"))
    -- app:get("register",    "/register",  r2(require "actions.register"))
    -- app:post("register",    "/register", r2(require "actions.register"))

    app:match("logout",   "/logout",   function(self)
        -- Logout
        self.session.user  = nil
        return { redirect_to = self:url_for("homepage") }
    end)


    -- app:match("/log", respond_to({
    --     -- do common setup
    --     before = function(self)
    --         if self.session.current_user then
    --             self:write({ redirect_to = "homepage" })
    --         end
    --     end,
    --     -- render the view
    --     GET = function(self)
    --         return { render = true }
    --     end,
    --     -- handle the form submission
    --     POST = function(self)
    --         self.session.current_user =
    --             try_to_login(self.params.username, self.params.password)

    --         return { redirect_to = "/" }
    --     end
    -- }))

    return app
end

return auth
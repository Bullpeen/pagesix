function auth(app)

    app:match("password", "/password", function(self) end) -- stub
    app:match("login",    "/login",    function(self) end) -- stub
    app:match("logout",   "/logout",   function(self)
        -- Logout
        self.session.user  = nil
        return { redirect_to = self:url_for("homepage") }
    end)

    return app
end

return auth
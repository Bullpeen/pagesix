--- Admin URLs
-- @module src.admin

function admin(app)

    -- TODO : all the things
    app:get("/admin", function(self) return "Go away" end)

    return app
end

return admin
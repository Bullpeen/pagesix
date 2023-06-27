--- URLs model
-- @module src.urls

local r2    = require("lapis.application").respond_to

function urls(app)

    app:match("/domain/:domain",                      r2(require "actions.domain"))

    app:match("new",           "/new",                r2(require "actions.index"))
    app:match("top",           "/top",                r2(require "actions.index"))
    app:match("controversial", "/controversial",      r2(require "actions.index"))
    app:match("comments",      "/comments",           r2(require "actions.index"))

    app:match("all",           "/r/all",              function(self) end) -- stub
    app:match("popular",       "/r/popular",          function(self) end) -- stub
    app:match("random",        "/r/random",           function(self) end) -- stub

    app:match("submit",        "/submit",             function(self) end) -- stub

    app:match("about",         "/about",              function(self) end) -- stub
    app:match("help",          "/help",               function(self) end) -- stub
    app:match("contact",       "/contact",            function(self) end) -- stub

    return app
end

return urls
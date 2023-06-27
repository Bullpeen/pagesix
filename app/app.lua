--- Page Six - A Reddit Clone
-- @script pagesix
-- @author Michael Burns
-- @license Apache License v2.0

local lapis = require "lapis"
local r2    = require("lapis.application").respond_to
local after_dispatch = require("lapis.nginx.context").after_dispatch
local to_json = require("lapis.util").to_json
local console = require("lapis.console")

local app   = lapis.Application()

app:before_filter(function(self)
    after_dispatch(function()
        -- https://leafo.net/lapis/reference/configuration.html#performance-measurement
        print(to_json(ngx.ctx.performance))
    end)
end)

function app:default_route()
    ngx.log(ngx.NOTICE, "User hit unknown path " .. self.req.parsed_url.path)

    -- call the original implementaiton to preserve the functionality it provides
    return lapis.Application.default_route(self)
end

function app:handle_404()
    error("Failed to find route: " .. self.req.request_uri)
    return { status = 404, layout = true, "Not Found!" }
end

app:enable("etlua")

app.layout = require "views.layout"

app:match("homepage",   "/",              r2(require "actions.index"))
app:match("subreddits", "/subreddits(/:type)",       r2(require "actions.subreddits"))
app:match("subreddit",  "/r/:subreddit[%w]", r2(require "actions.subreddit"))
app:match("post",       "/r/:subreddit/comments/:post_id(/:title_stub)", r2(require "actions.post"))
app:match("comment",    "/r/:subreddit/comments/:post_id/:title_stub/:comment_id(/:q)", r2(require "actions.comment"))
app:match("profile",    "/user/:user_name(/:type)", r2(require "actions.user"))

app:match("/console", console.make()) -- only available in Development builds

require("src.admin")(app) -- Admin endpoints
require("src.api")(app)   -- API endpoints
require("src.auth")(app)  -- User-authenticated endpoints
require("src.urls")(app)  -- additional URLs

return app

--- Page Six - A Reddit Clone
-- @script pagesix
-- @author Michael Burns
-- @license AGPL

local lapis = require("lapis")
local r2 = require("lapis.application").respond_to
local after_dispatch = require("lapis.nginx.context").after_dispatch
-- local to_json = require("lapis.util").to_json
local console = require("lapis.console")

local app = lapis.Application()

app:before_filter(function(self)
	after_dispatch(function()
		-- https://leafo.net/lapis/reference/configuration.html#performance-measurement
		-- print(to_json(ngx.ctx.performance))
	end)
end)

function app:default_route()
	ngx.log(ngx.NOTICE, "Unknown path " .. self.req.parsed_url.path) -- luacheck: ignore

	-- call the original implementaiton to preserve the functionality it provides
	return lapis.Application.default_route(self)
end

function app:handle_404()
	error("Failed to find route: " .. self.req.request_uri .. "\n")
	return { status = 404, layout = true, "Not Found!" }
end

app:enable("etlua")

app.layout = require("views.layout")

app:match("homepage", "/", r2(require("actions.index"))) -- hot sort

-- best
-- hot
-- app:match("new", "/new", r2(require("actions.index")))
-- app:match("rising", "/rising", r2(require("actions.index")))
-- app:match("controversial", "/controversial", r2(require("actions.index")))
-- app:match("top", "/top", r2(require("actions.index")))


-- app:match("new_subreddit", "/r/:subreddit/new", r2(require("actions.r_subreddit")))
-- app:match("rising_subreddit", "/r/:subreddit/rising", r2(require("actions.index")))
-- app:match(
-- 	"controversial_subreddit",
-- 	"/r/:subreddit/controversial",
-- 	r2(require("actions.index"))
-- )
-- app:match("top_subreddit", "/r/:subreddit/top", r2(require("actions.index")))

app:match("user_profile", "/user/:user_name(/:type)", r2(require("actions.user")))

app:match("comments", "/comments", r2(require("actions.index")))
app:match("domains", "/domain/:domain", r2(require("actions.domain")))
app:match("subreddits", "/subreddits(/:type)", r2(require("actions.subreddits")))

-- app:match("subreddits",   "/subreddits/search",  r2(require "actions.subreddits"))
app:match("subscribed",   "/subscribed",    r2(require "actions.subscribed")) -- only for logged in users

-- meta subreddits
app:match("popular", "/r/popular", r2(require("actions.r_popular")))
app:match("all", "/r/all", r2(require("actions.r_all")))
app:match("random", "/r/random", r2(require("actions.r_random")))
app:match("subreddit", "/r/:subreddit", r2(require("actions.r_subreddit")))

app:match(
	"post",
	"/r/:subreddit/comments/:post_id[%w](/:title_stub)",
	r2(require("actions.post"))
)
app:match(
	"comment",
	"/r/:subreddit/comments/:post_id[%w]/:title_stub/:comment_id[%w](/:q)",
	r2(require("actions.comment"))
)

-- app:match("prefs", "/prefs", function(self) end) -- stub

-- app:match("about", "/about", function(self) end) -- stub
-- app:match("contact", "/contact", function(self) end) -- stub
-- app:match("help", "/help", function(self) end) -- stub
app:match("submit", "/submit", r2(require("actions.submit")))

app:get("/admin", function(self)
	return "Go away"
end)
app:match("/console", console.make()) -- only available in Development builds

-- require("src.api")(app) -- API endpoints
require("src.auth")(app) -- User-authenticated endpoints

return app

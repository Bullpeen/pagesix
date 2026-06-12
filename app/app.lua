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

-- Per-connection SQLite tuning. Lapis's sqlite backend has no connect hook, so
-- set these on the worker's connection on first request (persists for the
-- worker when code_cache is on; cheap to repeat when off). WAL + page_size are
-- already set persistently in migration [1].
local db_tuned = false
local function tune_sqlite()
	if db_tuned then return end
	db_tuned = true
	local db = require("lapis.db")
	pcall(db.query, "PRAGMA foreign_keys = ON") -- enforce the FK constraints
	pcall(db.query, "PRAGMA busy_timeout = 5000") -- wait, don't error, on WAL write locks
	pcall(db.query, "PRAGMA cache_size = -16000") -- ~16 MB page cache
	pcall(db.query, "PRAGMA synchronous = NORMAL")
end

app:before_filter(function(self)
	tune_sqlite()

	after_dispatch(function()
		-- https://leafo.net/lapis/reference/configuration.html#performance-measurement
		-- print(to_json(ngx.ctx.performance))
	end)

	-- Make the logged-in user and their subscriptions available to every view
	-- (the layout header renders `subs` as the "my subs" nav).
	if self.session and self.session.current_user then
		local user = require("models.users"):find({ user_name = self.session.current_user })
		if user then
			self.current_user = user
			self.subs = require("models.subscriptions"):subscribed_forums(user.id)
			self.unread_count = require("models.notifications"):unread_count(user.id)
		end
	end
end)

function app:default_route()
	if ngx and ngx.log then
		ngx.log(ngx.NOTICE, "Unknown path " .. self.req.parsed_url.path) -- luacheck: ignore
	end

	-- call the original implementaiton to preserve the functionality it provides
	return lapis.Application.default_route(self)
end

function app:handle_404()
	error("Failed to find route: " .. self.req.request_uri .. "\n")
	return { status = 404, layout = true, "Not Found!" }
end

app:enable("etlua")

app.layout = require("views.layout")

-- RSS output feeds (registered before the catch-alls; the literal `.rss`
-- segment takes precedence over the :sort / :subreddit params).
app:match("feed", "/.rss", r2(require("actions.feed")))
app:match("subreddit_feed", "/r/:subreddit/.rss", r2(require("actions.feed")))

app:match("homepage", "/(:sort)", r2(require("actions.index")))

-- app:match("comments", "/comments", r2(require("actions.index")))
app:match("domains", "/domain/:domain", r2(require("actions.domain")))
app:match("subreddits_search", "/subreddits/search", r2(require "actions.subreddits"))
-- An exact `/subreddits` route (like /login) takes precedence over the
-- `/(:sort)` homepage catch-all; the optional-group form did not.
app:match("subreddits", "/subreddits", r2(require("actions.subreddits")))
app:match("subreddits_type", "/subreddits/:type", r2(require("actions.subreddits")))
app:match("user_profile", "/user/:user_name(/:type)", r2(require("actions.user")))

-- meta subreddits (literal /r/all and /r/popular take precedence over the
-- /r/:subreddit param route below)
app:match("r_all", "/r/all(/:sort)", r2(require("actions.r_all")))
app:match("r_popular", "/r/popular(/:sort)", r2(require("actions.r_popular")))

app:match("search", "/search", r2(require("actions.search")))
app:match("r_random", "/r/random", r2(require("actions.r_random")))
app:match("subreddit", "/r/:subreddit(/:sort)", r2(require("actions.r_subreddit")))

app:match(
	"post",
	"/r/:subreddit/comments/:post_id[%d](/:title_stub)",
	r2(require("actions.post"))
)
app:match(
	"comment",
	"/r/:subreddit/comments/:post_id[%d]/:title_stub/:comment_id[%d]",
	r2(require("actions.comment"))
)

app:match(
	"/test/:comment_id[%d]",
	r2(require("actions.comment"))
)


-- app:match("about", "/about", function(self) end) -- stub
-- app:match("contact", "/contact", function(self) end) -- stub
-- app:match("help", "/help", function(self) end) -- stub

app:get("/admin", function(self) return "Go away" end)
app:match("/console", console.make()) -- only available in Development builds

-- require("src.api")(app) -- API endpoints
require("src.auth")(app) -- User-authenticated endpoints

return app

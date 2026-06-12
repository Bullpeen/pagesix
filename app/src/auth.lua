--- Auth URLs
-- @module src.auth

local cached = require("lapis.cache").cached
local r2 = require("lapis.application").respond_to

local function auth(app)
	-- only for logged in users
	app:match("subscribed",   "/subscribed",    r2(require "actions.subscribed"))
	app:match("submit", "/submit", r2(require("actions.submit")))
	app:match("vote", "/vote/post/:post_id[%d]/:direction", r2(require("actions.vote")))
	app:match("vote_comment", "/vote/comment/:comment_id[%d]/:direction", r2(require("actions.vote")))
	app:match("post_comment", "/post/:post_id[%d]/comment", r2(require("actions.comment_create")))
	app:match("create_subreddit", "/subreddit/create", r2(require("actions.create_subreddit")))
	app:match("subscribe", "/subscribe/:subreddit", r2(require("actions.subscribe")))
	app:match("comment_edit", "/comment/:comment_id[%d]/edit", r2(require("actions.comment_edit")))
	app:match("comment_delete", "/comment/:comment_id[%d]/delete", r2(require("actions.comment_delete")))
	app:match("post_edit", "/post/:post_id[%d]/edit", r2(require("actions.post_edit")))
	app:match("post_delete", "/post/:post_id[%d]/delete", r2(require("actions.post_delete")))
	app:match("save_post", "/post/:post_id[%d]/save", r2(require("actions.save")))
	app:match("hide_post", "/post/:post_id[%d]/hide", r2(require("actions.hide")))
	app:match("saved", "/saved", r2(require("actions.saved")))

	-- app:match("prefs", "/prefs", function(self) end) -- stub

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

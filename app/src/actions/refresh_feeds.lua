--- Moderator: refresh a subreddit's RSS/Atom feeds now (manual trigger).
-- @module action.refresh_feeds

local Users = require("models.users")
local Forum = require("src.models.forum")
local feed_import = require("src.utils.feed_import")
local Privileges = require("src.utils.privileges")

return {
	-- POST /r/:subreddit/feeds/refresh  -- subreddit moderators only
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return { redirect_to = self:url_for("homepage") }
		end

		if Privileges.can(user.id, sub, "manage_feeds") then
			feed_import.refresh_subreddit(sub.id)
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("subreddit", { subreddit = sub.name }) }
	end,
}

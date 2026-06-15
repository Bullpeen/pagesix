--- Moderator: manage a subreddit's RSS/Atom feeds (list + add/remove/toggle UI).
--- The mutating actions live in feed_add / feed_remove / feed_toggle; this is
--- the mod-only page that renders them.
-- @module action.feeds_manage

local Forum = require("src.models.forum")
local Feeds = require("src.models.feeds")

return {
	before = function(self)
		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
		-- current_user is set by the app before_filter when signed in.
		if not (self.current_user and Forum:can_moderate(self.current_user.id, sub)) then
			return self:write({
				redirect_to = self:url_for("subreddit", { subreddit = sub.name }),
			})
		end
		self.subreddit = sub.name
		self.feeds = Feeds:list(sub.id)
	end,

	GET = function(self)
		return { render = "feeds_manage" }
	end,
}

--- Moderator: enable/disable an RSS/Atom feed (the scheduler only fetches
--- enabled feeds). CSRF-guarded (global before_filter), mod-only, logged.
-- @module action.feed_toggle

local Forum = require("src.models.forum")
local Feeds = require("src.models.feeds")
local Modlog = require("src.models.modlog")

return {
	-- POST /r/:subreddit/feeds/:feed_id/toggle  -- subreddit moderators only
	POST = function(self)
		local user = self.current_user
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return { redirect_to = self:url_for("homepage") }
		end

		if Forum:can_moderate(user.id, sub) then
			local feed = Feeds:find({ id = tonumber(self.params.feed_id), sub_id = sub.id })
			if feed then
				local enabling = tonumber(feed.enabled) ~= 1
				Feeds:set_enabled(sub.id, feed.id, enabling)
				Modlog:create({
					mod_id = user.id,
					sub_id = sub.id,
					action = enabling and 8 or 9,
					reason = (enabling and "enabled feed " or "disabled feed ") .. feed.url,
				})
			end
		end

		return { redirect_to = self:url_for("feeds_manage", { subreddit = sub.name }) }
	end,
}

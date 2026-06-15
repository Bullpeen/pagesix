--- Moderator: remove an RSS/Atom feed from a subreddit. CSRF-guarded (global
--- before_filter), mod-only, recorded in the modlog. Imported posts stay.
-- @module action.feed_remove

local Forum = require("src.models.forum")
local Feeds = require("src.models.feeds")
local Modlog = require("src.models.modlog")

return {
	-- POST /r/:subreddit/feeds/:feed_id/remove  -- subreddit moderators only
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
			-- Scoped to the sub, so a mod can only remove their own sub's feeds.
			local removed = Feeds:remove(sub.id, self.params.feed_id)
			if removed then
				Modlog:create({
					mod_id = user.id,
					sub_id = sub.id,
					action = 7,
					reason = "removed feed " .. removed.url,
				})
			end
		end

		return { redirect_to = self:url_for("feeds_manage", { subreddit = sub.name }) }
	end,
}

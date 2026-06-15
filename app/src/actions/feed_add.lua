--- Moderator: add an RSS/Atom feed URL to a subreddit. CSRF-guarded (global
--- before_filter), mod-only, recorded in the modlog.
-- @module action.feed_add

local Forum = require("src.models.forum")
local Feeds = require("src.models.feeds")
local Modlog = require("src.models.modlog")

return {
	-- POST /r/:subreddit/feeds/add  -- subreddit moderators only
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
			local url = (self.params.url or ""):match("^%s*(.-)%s*$")
			-- Only accept http(s) URLs; the importer fetches these directly.
			if url ~= "" and url:match("^https?://") then
				Feeds:add(sub.id, url)
				Modlog:create({
					mod_id = user.id,
					sub_id = sub.id,
					action = 6,
					reason = "added feed " .. url,
				})
			end
		end

		return { redirect_to = self:url_for("feeds_manage", { subreddit = sub.name }) }
	end,
}

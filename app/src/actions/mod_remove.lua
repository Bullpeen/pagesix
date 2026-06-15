--- Moderator: remove/approve a post (toggles posts.locked, which hides it from
--- listings), recorded in the modlog.
-- @module action.mod_remove

local Users = require("models.users")
local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Modlog = require("src.models.modlog")
local Privileges = require("src.utils.privileges")

return {
	-- POST /post/:post_id/remove  -- subreddit moderators only
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local post = Posts:find(tonumber(self.params.post_id))
		if not post then
			return { redirect_to = self:url_for("homepage") }
		end

		local forum = Forum:find(post.sub_id)
		if Privileges.can(user.id, forum, "remove") then
			local removing = tonumber(post.locked) ~= 1
			post:update({ locked = removing and 1 or 0 })
			Modlog:create({
				mod_id = user.id,
				post_id = post.id,
				sub_id = post.sub_id,
				action = removing and 1 or 0,
				reason = removing and "removed" or "approved",
			})
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

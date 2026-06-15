--- Moderator: lock/unlock a post's comment thread (toggles posts.comments_locked).
--- A locked thread stays visible but rejects new comments/replies. Recorded in
--- the modlog. Distinct from `locked`, which the remove/approve flow uses.
-- @module action.lock

local Users = require("models.users")
local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Modlog = require("src.models.modlog")

return {
	-- POST /post/:post_id/lock  -- subreddit moderators only
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
		if Forum:can_moderate(user.id, forum) then
			local locking = tonumber(post.comments_locked) ~= 1
			post:update({ comments_locked = locking and 1 or 0 })
			Modlog:create({
				mod_id = user.id,
				post_id = post.id,
				sub_id = post.sub_id,
				action = locking and 2 or 3,
				reason = locking and "locked comments" or "unlocked comments",
			})
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

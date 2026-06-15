--- Moderator: sticky/unsticky a post (toggles posts.stickied). Stickied posts
--- are pinned to the top of their subreddit listing. Recorded in the modlog.
-- @module action.sticky

local Users = require("models.users")
local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Modlog = require("src.models.modlog")
local Privileges = require("src.utils.privileges")

return {
	-- POST /post/:post_id/sticky  -- subreddit moderators only
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
		if Privileges.can(user.id, forum, "sticky") then
			local pinning = tonumber(post.stickied) ~= 1
			post:update({ stickied = pinning and 1 or 0 })
			Modlog:create({
				mod_id = user.id,
				post_id = post.id,
				sub_id = post.sub_id,
				action = pinning and 4 or 5,
				reason = pinning and "stickied" or "unstickied",
			})
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

--- Delete post action (soft delete)
-- @module action.post_delete

local Users = require("models.users")
local Posts = require("src.models.posts")

return {
	-- POST /post/:post_id/delete  -- author only
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local post = Posts:find(tonumber(self.params.post_id))
		if post and post.user_id == user.id then
			post:update({ deleted = 1 })
		end

		return { redirect_to = self:url_for("homepage") }
	end,
}

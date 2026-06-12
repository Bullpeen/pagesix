--- Hide/unhide post (toggle)
-- @module action.hide

local Users = require("models.users")
local HiddenPosts = require("models.hidden_posts")

return {
	-- POST /post/:post_id/hide
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end
		if self.params.post_id then
			HiddenPosts:toggle(user.id, tonumber(self.params.post_id))
		end
		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

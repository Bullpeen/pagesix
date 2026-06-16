--- Edit post action (self-post body)
-- @module action.post_edit

local Users = require("models.users")
local Posts = require("src.models.posts")

return {
	-- POST /post/:post_id/edit  (form: body)  -- author only, self posts
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local post = Posts:find(tonumber(self.params.post_id))
		if post and post.user_id == user.id and tonumber(post.deleted) ~= 1 then
			if tonumber(post.is_self) == 1 then
				post:update({ body = self.params.body, edited = 1 })
			end
			-- Re-tag when the form supplied a tags field (works for link posts too).
			if self.params.tags ~= nil then
				require("src.models.tags"):set_for_post(post.id, self.params.tags)
			end
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

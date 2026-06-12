--- Edit comment action
-- @module action.comment_edit

local Users = require("models.users")
local Comments = require("models.comments")

return {
	-- POST /comment/:comment_id/edit  (form: body)  -- author only
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local comment = Comments:find(tonumber(self.params.comment_id))
		if comment and comment.user_id == user.id and tonumber(comment.deleted) ~= 1 then
			-- update() runs the body constraint; the `edited` flag marks it.
			comment:update({ body = self.params.body, edited = 1 })
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

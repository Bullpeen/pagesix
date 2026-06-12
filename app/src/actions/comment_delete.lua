--- Delete comment action (soft delete)
-- @module action.comment_delete

local Users = require("models.users")
local Comments = require("models.comments")

return {
	-- POST /comment/:comment_id/delete  -- author only
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local comment = Comments:find(tonumber(self.params.comment_id))
		if comment and comment.user_id == user.id then
			-- soft delete: thread() keeps the node as [deleted] so replies stay.
			comment:update({ deleted = 1 })
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

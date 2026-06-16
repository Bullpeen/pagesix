--- Accept (or unaccept) a comment as the answer to its post.
--- Allowed for the post's author (OP) or anyone with the `accept_answer`
--- privilege (moderators/owners/admins). Toggles posts.accepted_comment_id.
-- @module action.accept

local db = require("lapis.db")
local Users = require("models.users")
local Posts = require("src.models.posts")
local Comments = require("models.comments")
local Forum = require("src.models.forum")
local Privileges = require("src.utils.privileges")

return {
	-- POST /comment/:comment_id/accept
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local comment = Comments:find(tonumber(self.params.comment_id))
		local post = comment and Posts:find(comment.post_id)
		if not post then
			return { redirect_to = self:url_for("homepage") }
		end

		local is_op = tonumber(post.user_id) == tonumber(user.id)
		if is_op or Privileges.can(user.id, Forum:find(post.sub_id), "accept_answer") then
			-- Toggle: accepting the already-accepted comment clears it.
			if tonumber(post.accepted_comment_id) == tonumber(comment.id) then
				post:update({ accepted_comment_id = db.NULL })
			else
				post:update({ accepted_comment_id = comment.id })
			end
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

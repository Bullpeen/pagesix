--- Create comment action
-- @module action.comment_create

local Users = require("models.users")
local Posts = require("src.models.posts")
local Comments = require("models.comments")
local Notifications = require("models.notifications")
local Spam = require("src.utils.spam")

return {
	-- POST /post/:post_id/comment  (form: body, optional parent_comment_id)
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

		-- Only thread under a parent that actually belongs to this post.
		local parent_id, parent
		if self.params.parent_comment_id and self.params.parent_comment_id ~= "" then
			parent = Comments:find(tonumber(self.params.parent_comment_id))
			if parent and parent.post_id == post.id then
				parent_id = parent.id
			else
				parent = nil
			end
		end

		-- Bayesian spam check (fails open if untrained); drop spam silently like
		-- the existing redirect-based error path does.
		if Spam.is_spam(self.params.body) then
			self.errors = { "Your comment looks like spam." }
		else
			-- The Comments model's `body` constraint validates the text; create
			-- returns nil + error if it fails.
			local comment, err = Comments:create({
				post_id = post.id,
				user_id = user.id,
				parent_comment_id = parent_id,
				body = self.params.body,
				is_submitter = post.user_id == user.id and 1 or 0,
			})
			if not comment then
				self.errors = { err }
			else
				-- Notify the parent comment's author (reply) or the post's author
				-- (top-level comment), unless you're replying to yourself.
				local recipient = parent and parent.user_id or post.user_id
				if tonumber(recipient) ~= tonumber(user.id) then
					Notifications:notify(
						recipient,
						comment.id,
						parent_id and "comment_reply" or "post_reply"
					)
				end
			end
		end

		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

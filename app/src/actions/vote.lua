--- Vote action
-- @module action.vote

local Users = require("models.users")
local Comments = require("models.comments")
local Votes = require("src.models.votes")

local DIRECTIONS = { up = 1, down = 0 }

return {
	-- POST /vote/post/:post_id/:direction       (post vote)
	-- POST /vote/comment/:comment_id/:direction (comment vote)
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local upvote = DIRECTIONS[self.params.direction]
		if upvote == nil then
			return { redirect_to = self:url_for("homepage") }
		end

		if self.params.comment_id then
			-- A comment vote still records the post_id (the votes table keys on
			-- both); look it up from the comment.
			local comment = Comments:find(tonumber(self.params.comment_id))
			if comment then
				Votes:cast(user.id, comment.post_id, comment.id, upvote)
			end
		elseif self.params.post_id then
			Votes:cast(user.id, tonumber(self.params.post_id), nil, upvote)
		end

		-- Return to the page the vote was cast from.
		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

--- Vote action
-- @module action.vote

local Users = require("models.users")
local Posts = require("src.models.posts")
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
				-- Keep the content author's cached reputation current.
				Users:recompute_reputation(comment.user_id)
			end
		elseif self.params.post_id then
			local post = Posts:find(tonumber(self.params.post_id))
			if post then
				Votes:cast(user.id, post.id, nil, upvote)
				Users:recompute_reputation(post.user_id)
			end
		end

		-- Return to the page the vote was cast from.
		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

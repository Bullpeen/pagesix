--- Vote action
-- @module action.vote

local Users = require("models.users")
local Votes = require("src.models.votes")

local DIRECTIONS = { up = 1, down = 0 }

return {
	-- POST /vote/post/:post_id/:direction  (direction = up | down)
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local upvote = DIRECTIONS[self.params.direction]
		local post_id = tonumber(self.params.post_id)
		if upvote == nil or not post_id then
			return { redirect_to = self:url_for("homepage") }
		end

		Votes:cast(user.id, post_id, nil, upvote)

		-- Return to the page the vote was cast from.
		local referer = self.req.headers["referer"]
		return { redirect_to = referer or self:url_for("homepage") }
	end,
}

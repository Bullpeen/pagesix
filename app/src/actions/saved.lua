--- Saved posts listing
-- @module action.saved

local Users = require("models.users")
local Posts = require("src.models.posts")

return {
	-- GET /saved  (the current user's saved posts)
	before = function(self)
		if self.session.current_user then
			local user = Users:find({ user_name = self.session.current_user })
			if user then
				self.posts = Posts:get_listing({ saved_for = user.id })
			end
		end
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

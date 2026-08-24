--- Saved posts listing
-- @module action.saved

local Users = require("models.users")
local Posts = require("src.models.posts")
local P = require("src.utils.paginate_db")

-- Posts per listing page.
local PER_PAGE = 25

return {
	-- GET /saved  (the current user's saved posts)
	before = function(self)
		if self.session.current_user then
			local user = Users:find({ user_name = self.session.current_user })
			if user then
				local page, per_page, limit, offset = P.window(self.params.page, PER_PAGE)
				self.posts, self.pagination = P.finish(
					Posts:get_listing({ saved_for = user.id, limit = limit, offset = offset }),
					page,
					per_page
				)
			end
		end
	end,

	GET = function(self)
		return { render = "index" }
	end,
}

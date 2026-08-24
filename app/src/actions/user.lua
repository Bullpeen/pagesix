--- User action
-- @module action.user

local Users = require("models.users")
local Posts = require("src.models.posts")
local Comments = require("models.comments")
local paginate = require("src.utils.paginate")
local P = require("src.utils.paginate_db")

-- Posts (and comments) per page on a profile.
local PER_PAGE = 25

return {
	before = function(self)
		local user = Users:find({ user_name = self.params.user_name })

		-- Unknown user: redirect home instead of crashing on a nil index.
		if not user then
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		self.user_name = user.user_name
		self.created_at = user.created_at
		self.karma = Users:karma(user.id)
		self.reputation = user.reputation or 0
		self.trust_level = Users:trust_level(user.reputation)

		-- The posts/comments fragments expect rows with vote aggregates etc.,
		-- so use the same enriched queries the listing pages do (filtered to
		-- this user) rather than the raw relation rows. Both lists page off the
		-- same `?page=`; the shared nav advances when either still has more.
		-- Posts page in SQL; the comment list is still sliced in memory (see
		-- Comments:by_user). Both read the same `?page=`, and the shared nav
		-- advances while either still has more.
		local page, per_page, limit, offset = P.window(self.params.page, PER_PAGE)
		local posts_info, comments_info
		self.posts, posts_info = P.finish(
			Posts:get_listing({ user_id = user.id, limit = limit, offset = offset }),
			page,
			per_page
		)
		self.comments, comments_info = paginate(Comments:by_user(user.id), page, per_page)

		self.pagination = {
			page = page,
			has_prev = posts_info.has_prev,
			has_next = posts_info.has_next or comments_info.has_next,
		}
	end,

	GET = function(self)
		return { render = "user" }
	end,
}

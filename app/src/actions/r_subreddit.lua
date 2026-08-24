--- Subreddit action
-- @module action.subreddit

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local P = require("src.utils.paginate_db")

-- Posts per listing page.
local PER_PAGE = 25

return {
	before = function(self)
		local subreddit_name = self.params.subreddit
		local sort = self.params.sort or "hot"

		-- Look the subreddit up by name. (The old code mapped name -> the
		-- hardcoded object_types enum id, which only happens to match forum.id
		-- for the seeded subs and breaks for any user-created one.)
		local sub = Forum:find({ name = subreddit_name })
		if not sub then
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		self.subreddit = sub.name
		local since = require("src.utils.timewindow")(self.params.t)
		-- `sticky_first` puts the moderator-pinned posts at the top of the
		-- ORDER BY, keeping their relative order within the chosen sort -- the
		-- partition that used to be done in Lua after fetching everything.
		local page, per_page, limit, offset = P.window(self.params.page, PER_PAGE)
		local rows = Posts:get_listing({
			sub_id = sub.id,
			since = since,
			exclude_hidden_for = self.current_user and self.current_user.id,
			sort = sort,
			sticky_first = true,
			limit = limit,
			offset = offset,
		})
		self.posts, self.pagination = P.finish(rows, page, per_page)

		-- current_user is set by the app before_filter when signed in.
		if self.current_user then
			self.subscribed =
				require("models.subscriptions"):is_subscribed(self.current_user.id, sub.id)
			self.can_moderate = Forum:can_moderate(self.current_user.id, sub)
		end
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit" }
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

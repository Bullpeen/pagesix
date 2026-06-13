--- Subreddit action
-- @module action.subreddit

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")

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
		local sorted = Sort:sort(
			Posts:get_listing({
				sub_id = sub.id,
				since = since,
				exclude_hidden_for = self.current_user and self.current_user.id,
			}),
			sort
		)
		self.posts, self.pagination = require("src.utils.paginate")(sorted, self.params.page)

		-- current_user is set by the app before_filter when signed in.
		if self.current_user then
			self.subscribed =
				require("models.subscriptions"):is_subscribed(self.current_user.id, sub.id)
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

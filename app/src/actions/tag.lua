--- Tag listing: posts carrying a given tag, across all subreddits.
-- @module action.tag

local Posts = require("src.models.posts")
local Sort = require("src.utils.sort")
local Tags = require("src.models.tags")

return {
	before = function(self)
		-- Normalize the same way the model stores tags, so /t/Foo finds "foo".
		self.tag = Tags.normalize(self.params.tag)[1]
		if not self.tag then
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		local sort = self.params.sort or "hot"
		local sorted = Sort:sort(
			Posts:get_listing({
				tag = self.tag,
				exclude_hidden_for = self.current_user and self.current_user.id,
			}),
			sort
		)
		self.posts, self.pagination = require("src.utils.paginate")(sorted, self.params.page)
	end,

	GET = function(self)
		return { render = "tag" }
	end,
}

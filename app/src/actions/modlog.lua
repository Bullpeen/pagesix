--- Public moderation log for a subreddit
-- @module action.modlog

local Forum = require("src.models.forum")
local Modlog = require("src.models.modlog")

return {
	before = function(self)
		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
		self.subreddit = sub.name
		self.entries = Modlog:for_subreddit(sub.id)
	end,

	GET = function(self)
		return { render = "modlog" }
	end,
}

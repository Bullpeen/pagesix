--- User action
-- @module action.user

local db = require "lapis.db"
local Users = require "models.users"

return {
	before = function(self)

		-- TODO lookup id from params.user_name
		-- self.user = Users:find(params.user_name)
		self.posts = user:get_posts_paginated({
			per_page = 50
		}):get_page(1)

		self.comments = user:get_comments_paginated({
			per_page = 50
		}):get_page(1)
	end,

	GET = function(self)
		return { render = "user" }
	end
}

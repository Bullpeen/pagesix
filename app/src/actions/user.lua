--- User action
-- @module action.user

local db = require("lapis.db")
local Users = require("models.users")

return {
	before = function(self)
		local user_name = self.params.user_name

		local uid = Users:get_id_from_name(user_name)
		-- TODO lookup id from params.user_name
		-- local res = db.select("id FROM 'users' WHERE user_name=?", user_name)
		if not uid then
			print("User is invalid: " .. user_name)
			return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- local user_id = res[1].id
		-- print("User is valid: " .. user_id)
		local user = Users:find(uid)

		-- TODO paginate
		-- TODO use View, Index
		self.comments = user:get_all_comments(uid)
		print("Number of comments: " .. #self.comments)

		-- TODO implement
		-- self.comments = user:get_all_posts(uid)
		-- print("Number of posts: " .. #self.comments)
	end,

	GET = function(self)
		return { render = "user" }
	end,
}

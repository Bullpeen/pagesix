--- Submit action
-- @module action.submit

local Posts = require("models.posts")

return {
	before = function(self) end,

	GET = function(self)
		return { render = "submit" }
	end,

	POST = function(self)
		print(
			"self is "
				.. self.params.url
				.. ", "
				.. self.params.title
		)

		if self.params.passwd == self.params.passwd2 then
			local s, err = Posts:create({
				user_id = 1,
                sub_id = 1,
                title = self.params.title,
                permalink = math.random(1000000),
                url = self.params.url,
			})
			if not err then
				self.session.current_user = s.user_name
			else
				print("error creating " .. self.params.name)
				print(err)
			end
		end
	end,
}

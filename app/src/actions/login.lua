-- local db = require("lapis.db")

-- local csrf = require("lapis.csrf")

local Users = require("models.users")

-- local capture_errors = require("lapis.application").capture_errors

-- local app = lapis.Application()

-- app:get("form", "/form", function(self)
--     local csrf_token = csrf.generate_token(self)
--     self:html(function()
--         form({ method = "POST", action = self:url_for("form") }, function()
--         input({ type = "hidden", name = "csrf_token", value = csrf_token })
--         input({ type = "submit" })
--         end)
--     end)
-- end)

-- app:post("form", "/form", capture_errors(function(self)
--     csrf.assert_token(self)
--     return "The form is valid!"
-- end))

--- Domain action
-- @module action.domain

return {
	before = function(self)
		-- if self.session.current_user then
		-- self.user = self.session.current_user or "Anon"
		-- self:write({ redirect_to = self:url_for("homepage") })
		-- end
	end,

	GET = function(self)
		return { render = "login" }
	end,

	POST = function(self)
		-- TODO lookup user_name in Users table, compare password to user_pass

		if self.params.username then
			self.user = Users:find({user_name = self.params.username, user_pass = self.params.password})

			-- self.user = db.select(
			-- 	"* FROM users WHERE user_name = ? AND user_pass = ? LIMIT 1",
			-- 	self.params.username,
			-- 	self.params.password
			-- )

			-- self.user = self.account[1]
			if self.user then
				print("Found user: " .. self.user.user_name)
			else
				print("USER NOT FOUND")
				return
			end
		else
			print("NO USERNAME SUPPLIED")
			return
		end

		self.session.current_user = self.user.user_name

		return { redirect_to = "/" }
	end,
}

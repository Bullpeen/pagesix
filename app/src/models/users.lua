--- Users model
-- @module models.users

local db = require("lapis.db")
local Model = require("lapis.db.model").Model

local Users, Users_mt = Model:extend("users", {
	timestamp = true,

	-- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for/using-the-url-key-method
	url_key = function(self, route_name)
		return self.id
	end,

	-- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for/passing-an-object-to-url-for
	url_params = function(self, req, ...)
		local res = db.find(self.id)
		return "user_profile", { id = res.user_name }, ...
	end,

	constraints = {
		--- Apply constraints when updating/inserting a User row, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		user_name = function(self, value)

			-- TODO : check if value is in reserved names
			-- if db:find("reserved_usernames", { user_name = value }) then
			-- 	return nil, "Username is reserved"
			-- end

			if value then
				-- check for valid length (2-64]
				if string.len(value) >= 64 then
					return nil, "Username must be less than 64 characters"
				end

				if string.len(value) <= 2 then
					return nil, "Username must be more than 2 characters"
				end
			else
				-- print("ERROR, value is empty")
				return nil, "value is empty"
			end
		end,

		user_pass = function(self, value)
			-- enforce password length requirements
			local password_minimum_length = 7
			local password_maximum_length = 64 -- 4096
			if value then
				if string.len(value) < password_minimum_length then
					return string.format("Password must be at least %s characters", password_minimum_length)
				end
				if string.len(value) > password_maximum_length then
					return string.format("Password must no more than %s characters", password_maximum_length)
				end
			else
				print("ERROR, value is empty")
			end
		end,

		user_email = function(self, value)
			-- value must contain '@'
			if value and not string.find(value, "@") then
				return nil, "Email must contain '@'"
			end
		end,
	},

	relations = {
		{ "user_profile", has_one = "UserProfiles" },
		{ "subscriptions", has_many = "Subscriptions" },
		{ "posts", has_many = "Posts" },
		{ "votes", has_many = "Votes" },
		{ "comments", has_many = "Comments" },
		-- TODO: moderation is currently stored as a CSV in forum.moderator_ids,
		-- so there is no `moderator_id` FK column to key a relation off, and there
		-- is no `Subreddits` model. Re-enable once a `moderators` join table exists.
		-- {
		-- 	"moderates",
		-- 	has_many = "Forum",
		-- 	order = "id desc",
		-- 	key = "moderator_id"
		-- },
		{
			"authored_posts",
			has_many = "Posts",
			where = { deleted_at = nil },
			order = "id desc",
			key = "user_id",
		},
		{
			"authored_comments",
			has_many = "Comments",
			where = { deleted_at = nil },
			order = "id desc",
			key = "user_id",
		},
	},
})

function Users_mt:get_name_from_id(id)
	local res = db.select("user_name from users WHERE id=?", id)
	return res[1]
end

function Users_mt:get_id_from_name(name)
	local res = db.select("id from users WHERE user_name=?", name)
	return res[1]
end

return Users

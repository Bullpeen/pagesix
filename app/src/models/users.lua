--- Users model
-- @module models.users

local db = require("lapis.db")
local Model = require("lapis.db.model").Model

local Subreddits = Model:extend("subreddits") -- TODO don't hardcode `1`

-- local Users  = Model:extend("users")
local Users, Users_mt = Model:extend("users", {
	url_params = function(self, req, ...)
		return "user_profile", { id = self.id }, ...
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
		{ "subscriptions", has_many = "Subscriptions" },
		{ "posts", has_many = "Posts" },
		{ "comments", has_many = "Comments" },
		{ "moderates", has_many = "Subreddits", order = "id desc", key = "moderator_id" },
		{
			"authored_posts",
			has_many = "Posts",
			-- where = {deleted = false},
			order = "id desc",
			key = "user_id",
		},
		{
			"authored_comments",
			has_many = "Comments",
			where = {deleted = false},
			order = "id desc",
			key = "user_id",
		},
	},
})

print("RUNNING MODELS.Users")

--- Create a new user
-- @tparam table params User data
-- @tparam string raw_password Raw password
-- @treturn boolean success
-- @treturn string error
-- function Users:new(params, raw_password) -- TODO use built-in :create() ?
	-- Check if username is unique
	-- do
	-- 	local unique, err = self:is_unique(params.name)
	-- 	if not unique then
	-- 		return nil, err
	-- 	end
	-- end

	-- TODO: Verify password
-- 	if passwd == passwd2 then
-- 		local u = {
-- 			user_name = params.name,
-- 			user_email = params.email,
-- 			user_pass = params.passwd,
-- 			over_18 = False,
-- 			verified = False,
-- 		}

-- 		local user, err = Users:create(u)
-- 	end

-- 	return user and user or nil, { "err_create_user", { params.name } }
-- end

-- Get the user's display name
-- @treturn string user_name
-- this method will be available on all User instances
function Users_mt:get_display_name()
	return self.display_name or self.user_name
end

function Users_mt:get_name_from_id(id)
	local res = db.select("user_name from users WHERE id=?", id)
	return res[1]
end

function Users_mt:get_id_from_name(name)
	local res = db.select("id from users WHERE user_name=?", name)
	return res[1]
end

--- Get all users
-- @treturn table users List of users
function Users_mt:get_all_comments(uid)
	-- loop up number of rows in subreddits table
	-- local res = db.select("count(*) FROM 'subreddits'")
	-- local n = res[1]["count(*)"]
	local n = Subreddits:count()

	local all_comments = {}

	-- loop over all subreddits
	-- TODO index subreddit_id, post_id, comment_id, user_id
	for _ = 1, n do
		-- local subreddit = db.select("* FROM 'subreddits' WHERE id=?", i)
		-- local id = subreddit[1].id


		-- SELECT COUNT(*) score, a.title, a.url, a.permalink, over_18, locked
		-- FROM ? a
		-- INNER JOIN ? b ON a.id=b.post_id
		-- WHERE a.locked = 0 AND b.comment_id IS NULL
		-- GROUP BY a.id, b.post_id
		-- ORDER BY COUNT(*) DESC;


		local comments = db.select(
			[[
				COUNT(*) score, a.body, b.user_name
				FROM ? a
				INNER JOIN ? b ON a.user_id = b.id
				WHERE a.deleted = 0
				GROUP BY a.user_id, b.id
				ORDER BY COUNT(*) DESC;
			]],
			"comments",
			"users",
			uid)
		require 'pl.pretty'.dump(comments)

		for _, v in ipairs(comments) do
			all_comments[#all_comments + 1] = v
			-- all_comments[#all_comments + k]['subreddit_id'] = subreddit[1].id
		end
	end
	-- Posts:find({user_id = uid})
	return all_comments
end

--- Given a User, return their subreddit subscriptions
-- @tparam table user
-- @treturn table subscriptions
function Users:get_subscriptions(user)
	-- TODO
	-- local subscriptions = Subscriptions:find(user.id)
	local subscriptions = db.select("* from 'subscriptions' where user_id=?", user.id)
	return subscriptions
end

return Users

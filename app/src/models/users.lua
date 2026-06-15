--- Users model
-- @module models.users

local db = require("lapis.db")
local Model = require("lapis.db.model").Model

local Users = Model:extend("users", {
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
			if not value or value == "" then
				return "Username is required"
			end
			-- check for valid length (2-64]
			if string.len(value) >= 64 then
				return "Username must be less than 64 characters"
			end
			if string.len(value) <= 2 then
				return "Username must be more than 2 characters"
			end
			-- Reserved usernames live in the reserved_usernames table (seeded in
			-- migration [2]); block registration of any of them.
			local taken =
				db.select("1 FROM reserved_usernames WHERE user_name = ? LIMIT 1", value:lower())
			if taken[1] then
				return "Username is reserved"
			end
		end,

		user_pass = function(self, value)
			-- enforce password length requirements
			local password_minimum_length = 7
			local password_maximum_length = 64 -- 4096
			if value then
				if string.len(value) < password_minimum_length then
					return string.format(
						"Password must be at least %s characters",
						password_minimum_length
					)
				end
				if string.len(value) > password_maximum_length then
					return string.format(
						"Password must no more than %s characters",
						password_maximum_length
					)
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

--- Karma: net score (upvotes - downvotes) of all votes cast on this user's
-- posts and comments.
-- @tparam number user_id
-- @treturn number
function Users:karma(user_id)
	local row = db.select([[
		COALESCE((
			SELECT SUM(CASE WHEN v.upvote = 1 THEN 1 ELSE -1 END)
			FROM votes v JOIN posts p ON v.post_id = p.id
			WHERE v.comment_id IS NULL AND p.user_id = ]] .. tonumber(user_id) .. [[
		), 0) + COALESCE((
			SELECT SUM(CASE WHEN v.upvote = 1 THEN 1 ELSE -1 END)
			FROM votes v JOIN comments c ON v.comment_id = c.id
			WHERE c.user_id = ]] .. tonumber(user_id) .. [[
		), 0) AS karma]])
	return tonumber(row[1].karma) or 0
end

--- Recompute and persist a user's cached `reputation` (their live karma).
-- Called on every vote so the column stays current; returns the new value.
-- @tparam number user_id
-- @treturn number
function Users:recompute_reputation(user_id)
	local rep = self:karma(user_id)
	local user = self:find(user_id)
	if user then
		user:update({ reputation = rep })
	end
	return rep
end

-- Reputation thresholds, highest first. A user's trust level is the first band
-- whose `min` they meet. Used for profile badges and (later) gating new-user
-- behaviour like the post queue.
local TRUST_LEVELS = {
	{ level = "veteran", min = 250 },
	{ level = "trusted", min = 100 },
	{ level = "member", min = 10 },
	{ level = "new", min = nil }, -- floor: everyone else
}

--- Map a reputation score to a trust level name.
-- @tparam number reputation
-- @treturn string "new" | "member" | "trusted" | "veteran"
function Users:trust_level(reputation)
	reputation = tonumber(reputation) or 0
	for _, band in ipairs(TRUST_LEVELS) do
		if band.min == nil or reputation >= band.min then
			return band.level
		end
	end
	return "new"
end

return Users

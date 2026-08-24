--- Users model
-- @module models.users

local db = require("lapis.db")
local Model = require("lapis.db.model").Model
local Email = require("src.utils.email")

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
				-- A missing value is an error, like user_name above. Returning
				-- nothing here (after a `print` nobody sees) let a row with no
				-- password at all be inserted.
				return "Password is required"
			end
		end,

		user_email = function(self, value)
			-- Email is optional; when one is given it must be a valid address.
			-- (The previous check returned `nil, msg` -- a falsy first value, so
			-- Lapis never treated it as an error and nothing was validated.)
			if value and value ~= "" and not Email.is_valid(value) then
				return "Enter a valid email address"
			end
		end,
	},

	relations = {
		{ "subscriptions", has_many = "Subscriptions" },
		{ "posts", has_many = "Posts" },
		{ "votes", has_many = "Votes" },
		{ "comments", has_many = "Comments" },
		-- Live (not soft-deleted) authored rows. These filtered on
		-- `deleted_at = nil`, which was two mistakes at once: posts and comments
		-- carry an integer `deleted` flag and have no `deleted_at` column, and a
		-- `nil` value in a Lua table means the key is simply absent -- so the
		-- clause was empty and nothing was filtered. `deleted = 0` is the real
		-- condition. (`db.NULL` is what expresses "IS NULL" to Lapis.)
		{
			"authored_posts",
			has_many = "Posts",
			where = { deleted = 0 },
			order = "id desc",
			key = "user_id",
		},
		{
			"authored_comments",
			has_many = "Comments",
			where = { deleted = 0 },
			order = "id desc",
			key = "user_id",
		},
	},
})

--- Name of the synthetic account reserved for authorless content. Seeded by
-- migration [10] (and backfilled by [111]) with an unusable password, so it can
-- never be logged into. Named here so migrations and app code share one
-- spelling of it.
Users.ANONYMOUS = "anonymous_coward"

--- The synthetic anonymous account, or nil if the seed migration has not run.
-- @treturn table|nil
function Users:anonymous()
	return self:find({ user_name = Users.ANONYMOUS })
end

--- The synthetic anonymous account, creating it if it is not there yet.
-- Idempotent. Its password is the bcrypt digest of a value nobody holds, so
-- `Password.verify` can never match it and the account cannot be logged into.
-- Called from migrations [10]/[111] and from `delete_account`, which needs the
-- row to exist before it can reassign anything to it.
-- @treturn table the anonymous user row
function Users:ensure_anonymous()
	local existing = self:anonymous()
	if existing then
		return existing
	end
	local Password = require("src.utils.password")
	local unusable = Password.hash("anonymous-" .. tostring(os.time()) .. tostring(os.clock()))
	local user, err = self:create({
		user_name = Users.ANONYMOUS,
		user_email = "anonymous@localhost",
		user_pass = unusable,
	})
	-- Fail loudly: silently dropping this is the bug migration [10] shipped with.
	assert(user, "could not create " .. Users.ANONYMOUS .. ": " .. tostring(err))
	return user
end

-- Rows that belong to the person rather than to the site: destroyed outright
-- when an account is deleted. (`moderators` and `user_profiles` were on this
-- list until migration [113] dropped both tables.)
--
-- Migration [115] also gives each of these `ON DELETE CASCADE`, so the database
-- enforces the same thing. Deleting them here as well is deliberate, not
-- redundant: a cascade only fires when `PRAGMA foreign_keys = ON`, which is set
-- per connection (app.lua's tune_sqlite, and the spec helper) -- so on a
-- connection that missed the pragma, cascade would quietly not happen. The
-- explicit deletes do not depend on it.
local PERSONAL_TABLES = {
	{ "subscriptions", "user_id" },
	{ "saved_posts", "user_id" },
	{ "hidden_posts", "user_id" },
	{ "notifications", "user_id" },
	{ "password_resets", "user_id" },
	{ "oauth_identities", "user_id" },
	{ "roles", "user_id" },
	{ "site_roles", "user_id" },
}

-- Authored/attributed rows: kept, but reassigned to the anonymous account so
-- threads, communities and the moderation log stay readable. `votes` is handled
-- separately (see below) because of its uniqueness constraint.
local REASSIGNED_TABLES = {
	{ "posts", "user_id" },
	{ "comments", "user_id" },
	{ "forum", "creator_id" },
	{ "modlog", "mod_id" },
}

--- Permanently delete an account.
--
-- Authored content survives, reassigned to `Users.ANONYMOUS`: deleting an
-- account should not blow holes in other people's comment threads or orphan a
-- community. Everything personal -- subscriptions, saved/hidden posts, the
-- inbox, credentials, OAuth links, roles -- is destroyed.
--
-- Votes are reassigned rather than deleted so scores do not silently shift when
-- someone leaves; `UPDATE OR IGNORE` skips any row that would collide with a
-- vote the anonymous account already holds, and the leftovers are removed.
--
-- Runs in a transaction: every foreign key into `users` is NO ACTION, so a
-- partial run would leave the row undeletable.
--
-- @tparam number user_id
-- @treturn boolean|nil true on success, nil + message otherwise
function Users:delete_account(user_id)
	local user = self:find(user_id)
	if not user then
		return nil, "No such user"
	end
	if user.user_name == Users.ANONYMOUS then
		return nil, "The anonymous account cannot be deleted"
	end

	local anon = self:ensure_anonymous()
	db.query("BEGIN")
	local ok, err = pcall(function()
		for _, spec in ipairs(REASSIGNED_TABLES) do
			db.update(spec[1], { [spec[2]] = anon.id }, { [spec[2]] = user.id })
		end
		-- Keep the vote where the anonymous account has none for that target;
		-- drop the row where it already does (UNIQUE(user_id, post_id, comment_id)).
		db.query("UPDATE OR IGNORE votes SET user_id = ? WHERE user_id = ?", anon.id, user.id)
		db.query("DELETE FROM votes WHERE user_id = ?", user.id)

		for _, spec in ipairs(PERSONAL_TABLES) do
			db.delete(spec[1], { [spec[2]] = user.id })
		end
		db.delete("users", { id = user.id })
	end)
	if not ok then
		db.query("ROLLBACK")
		return nil, tostring(err)
	end
	db.query("COMMIT")
	return true
end

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

-- New rows arrive with their external id already set (see utils/public_id).
require("src.utils.public_id").mint_on_create(Users)

return Users

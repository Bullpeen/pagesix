--- Password reset tokens (one-shot, time-limited)
-- @module models.password_resets

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local PasswordResets = Model:extend("password_resets", {
	timestamp = true,
	relations = {
		{ "user", belongs_to = "Users" },
	},
})

-- Tokens are valid for one hour.
local TTL_SECONDS = 60 * 60

--- Issue a fresh reset token for a user, replacing any outstanding ones.
-- @treturn string the new token
function PasswordResets:issue(user_id)
	db.delete("password_resets", { user_id = user_id })
	self:create({
		user_id = user_id,
		token = require("src.utils.token").hex(32),
		expires_at = tostring(os.time() + TTL_SECONDS),
	})
	-- Re-read so callers get the stored token (and only the latest row).
	return self:find({ user_id = user_id }).token
end

--- Return the row for a still-valid token, or nil. Expired tokens are pruned.
function PasswordResets:valid(token)
	if not token or token == "" then
		return nil
	end
	local row = self:find({ token = token })
	if not row then
		return nil
	end
	if tonumber(row.expires_at or 0) < os.time() then
		row:delete()
		return nil
	end
	return row
end

return PasswordResets

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

--- A url-safe random token. Prefers openssl's CSPRNG; falls back to math.random
-- only if luaossl is unavailable (it ships in the image, so this is belt-and-
-- suspenders for the native lint loop).
local function generate_token()
	local ok, rand = pcall(require, "openssl.rand")
	if ok then
		local bytes = rand.bytes(32)
		return (bytes:gsub(".", function(c)
			return string.format("%02x", string.byte(c))
		end))
	end
	local chars = {}
	for i = 1, 48 do
		chars[i] = string.char(math.random(97, 122))
	end
	return table.concat(chars)
end

--- Issue a fresh reset token for a user, replacing any outstanding ones.
-- @treturn string the new token
function PasswordResets:issue(user_id)
	db.delete("password_resets", { user_id = user_id })
	self:create({
		user_id = user_id,
		token = generate_token(),
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

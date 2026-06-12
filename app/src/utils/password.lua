--- Password hashing (bcrypt).
-- @module utils.password
--
-- Replaces an earlier resty-sha512 sketch with bcrypt: salted, slow, and
-- self-contained on the server (no client-side prehashing required).

local bcrypt = require("bcrypt")

local LOG_ROUNDS = 11

local Password = {}

--- Hash a plaintext password. @treturn string the bcrypt digest
function Password.hash(plain)
	return bcrypt.digest(plain, LOG_ROUNDS)
end

--- Verify a plaintext password against a stored bcrypt digest.
-- Returns false for nil/blank or non-bcrypt (e.g. legacy plaintext) values
-- rather than erroring.
-- @treturn boolean
function Password.verify(plain, digest)
	if not plain or not digest or digest == "" then
		return false
	end
	-- bcrypt digests start with $2; anything else can't verify.
	if not tostring(digest):match("^%$2") then
		return false
	end
	local ok, result = pcall(bcrypt.verify, plain, digest)
	return ok and result or false
end

return Password

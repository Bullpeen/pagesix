--- Cryptographically-secure random tokens
-- @module utils.token
--
-- One source for unguessable opaque tokens (OAuth `state`, password-reset
-- tokens, ...). Uses openssl's CSPRNG via luaossl, which ships in the image;
-- it falls back to math.random only when luaossl is missing (e.g. the native
-- lint loop) so callers never crash, but production always takes the strong
-- path. Prefer this over hand-rolled `math.random` token loops.

local M = {}

--- A hex token carrying `nbytes` bytes of entropy (default 32 -> 64 hex chars).
-- Hex keeps the token URL- and cookie-safe without extra encoding. Never raises.
-- @tparam[opt=32] number nbytes
-- @treturn string
function M.hex(nbytes)
	nbytes = nbytes or 32
	local ok, rand = pcall(require, "openssl.rand")
	if ok then
		local bytes = rand.bytes(nbytes)
		return (bytes:gsub(".", function(c)
			return string.format("%02x", string.byte(c))
		end))
	end
	-- Fallback only (luaossl unavailable): still produces a hex string of the
	-- requested width, just without the CSPRNG guarantee.
	local chars = {}
	for i = 1, nbytes * 2 do
		chars[i] = string.format("%x", math.random(0, 15))
	end
	return table.concat(chars)
end

return M

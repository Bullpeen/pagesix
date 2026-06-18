--- RFC-4122 v4 UUIDs for the API's stable external ids
-- @module utils.uuid
--
-- The API exposes a `public_id` (uuid) per row so callers reference an opaque,
-- stable identifier instead of the guessable auto-increment `id`. UUIDs are
-- minted once and stored (see migration [109] / utils.api_serialize), so they
-- must be stable across calls -- generating one on every read would not be.
--
-- Source of randomness, in order of preference:
--   1. sqlean's `uuid4()` SQL function, when the extension bundle is loaded onto
--      Lapis's connection (the production/Docker path -- "use sqlean wherever
--      possible"). See docs/sqlean-plan.md, which earmarked `uuid` for the API.
--   2. openssl's CSPRNG (luaossl, already shipped for utils.token), formatted as
--      a v4 UUID -- the path the test suite and `lapis migrate` take, since the
--      sqlean `.so` is not loaded there.
--   3. math.random, only if neither is available, so callers never crash.

local M = {}

-- Format 16 raw bytes as a canonical v4 UUID string, stamping the version
-- (nibble 13 -> 4) and variant (nibble 17 -> 8..b) bits per RFC 4122.
local function format_v4(bytes)
	local b = { string.byte(bytes, 1, 16) }
	b[7] = (b[7] % 16) + 0x40 -- version 4
	b[9] = (b[9] % 64) + 0x80 -- variant 10xx
	local hex = {}
	for i = 1, 16 do
		hex[i] = string.format("%02x", b[i])
	end
	return table.concat({
		table.concat(hex, "", 1, 4),
		table.concat(hex, "", 5, 6),
		table.concat(hex, "", 7, 8),
		table.concat(hex, "", 9, 10),
		table.concat(hex, "", 11, 16),
	}, "-")
end

-- sqlean's uuid4(), if the extension is loaded onto Lapis's connection. Returns
-- the string or nil (never raises) so we fall through to the openssl path.
local function from_sqlean()
	if not require("src.utils.sqlite_ext").load() then
		return nil
	end
	local ok, rows = pcall(require("lapis.db").select, "uuid4() AS u")
	if ok and rows and rows[1] and type(rows[1].u) == "string" and #rows[1].u == 36 then
		return rows[1].u
	end
	return nil
end

-- 16 CSPRNG bytes from openssl, formatted as a v4 UUID, or nil if luaossl is
-- unavailable (e.g. the native lint loop).
local function from_openssl()
	local ok, rand = pcall(require, "openssl.rand")
	if not ok then
		return nil
	end
	return format_v4(rand.bytes(16))
end

-- Last-resort fallback: 16 math.random bytes. No CSPRNG guarantee, but still a
-- well-formed, unique-enough v4 string so the column never goes unfilled.
local function from_math()
	local bytes = {}
	for i = 1, 16 do
		bytes[i] = string.char(math.random(0, 255))
	end
	return format_v4(table.concat(bytes))
end

--- Generate a fresh v4 UUID string (36 chars, lowercase, hyphenated).
-- Never raises.
-- @treturn string
function M.generate()
	return from_sqlean() or from_openssl() or from_math()
end

return M

--- Email validation
-- @module utils.email
--
-- Validates an RFC 5322 addr-spec with lpeg_patterns (already a dependency)
-- rather than the previous "does it contain an @" check. Loaded defensively: if
-- lpeg_patterns is somehow unavailable we fall back to a minimal local@domain
-- check so user creation never hard-fails on a missing module.

local M = {}

-- Compiled once: the whole string must be a single mailbox (P(-1) anchors the
-- end, so trailing junk fails).
local matcher
do
	local ok_lpeg, lpeg = pcall(require, "lpeg")
	local ok_email, email = pcall(require, "lpeg_patterns.email")
	if ok_lpeg and ok_email then
		matcher = email.mailbox * lpeg.P(-1)
	end
end

--- Whether `s` is a syntactically valid email address. Empty/non-string is
-- false (callers decide whether an address is required).
-- @tparam string s
-- @treturn boolean
function M.is_valid(s)
	if type(s) ~= "string" or s == "" then
		return false
	end
	if matcher then
		return matcher:match(s) ~= nil
	end
	-- Fallback: a local part, one @, a domain, and no whitespace.
	return s:match("^[^@%s]+@[^@%s]+$") ~= nil
end

return M

--- URL helpers
-- @module utils.url
--
-- Thin wrapper over luasocket's socket.url, a real RFC-3986 parser. It handles
-- ports, userinfo, IPv6 literals and scheme-less inputs that the old
-- `^%w+://([^/]+)` pattern mishandled, and gives us one place to derive a link
-- post's display domain instead of repeating the pattern at each call site.

local M = {}

-- Loaded defensively: if luasocket somehow isn't present we fall back to the
-- previous pattern rather than break post rendering.
local ok_url, url = pcall(require, "socket.url")

--- The display domain (host) of a URL: lowercased, port stripped, and a leading
-- "www." removed so "www.example.com" and "example.com" group together (the
-- way reddit shows link domains). Returns "" when there is no host (relative or
-- malformed URL), preserving the previous nil-safe behaviour.
-- @tparam string u
-- @treturn string
function M.domain(u)
	if not u or u == "" then
		return ""
	end
	if ok_url then
		local ok, parsed = pcall(url.parse, u)
		local host = ok and parsed and parsed.host
		if host and host ~= "" then
			return (host:lower():gsub("^www%.", ""))
		end
		return ""
	end
	-- Fallback (luasocket unavailable): the previous pattern; host may keep a port.
	return (u:match("^%w+://([^/]+)") or "")
end

return M

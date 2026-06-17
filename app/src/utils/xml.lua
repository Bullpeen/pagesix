--- XML helpers
-- @module utils.xml

local M = {}

-- XML predefined entities. We emit &apos; (valid in XML) rather than an HTML
-- escaper's &#39;, so feeds/sitemaps stay byte-for-byte what they were.
local ENT = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }

--- Escape a value for inclusion in XML text or attributes; nil becomes "".
-- @tparam any s
-- @treturn string
function M.escape(s)
	return (tostring(s or ""):gsub("[&<>\"']", ENT))
end

return M

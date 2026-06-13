--- Read and JSON-decode a file, tolerating a missing/unreadable file.
-- @module utils.read_json

local io = require("io")
local json = require("cjson")

--- @tparam string path filesystem path to a JSON document
-- @treturn table|nil the decoded contents, or nil if the file can't be opened.
--   (A malformed file still raises, so seeding fails loudly rather than silently
--   importing nothing.)
return function(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return json.decode(content)
end

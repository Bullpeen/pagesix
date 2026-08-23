--- Tagged application logging.
-- @module utils.log
--
-- One place to write a diagnostic. Under OpenResty this goes to `ngx.log` so
-- entries land in nginx's error log with a real severity; outside it (CLI
-- scripts, migrations, the busted suite) it falls back to stderr. `print`
-- writes to stdout, which nginx does not capture, so a `print` in request code
-- is a message nobody ever reads.
--
--     local log = require("src.utils.log").tag("post")
--     log.error("no such subreddit: " .. tostring(name))

local M = {}

-- ngx.<LEVEL> constants exist only under OpenResty; the labels are used for the
-- stderr fallback, which has no severity of its own.
local LEVELS = {
	error = { ngx_level = "ERR", label = "ERROR" },
	warn = { ngx_level = "WARN", label = "WARN" },
	notice = { ngx_level = "NOTICE", label = "NOTICE" },
}

local function emit(level, tag, msg)
	local line = "[" .. tag .. "] " .. tostring(msg)
	local ngx_level = ngx and ngx[level.ngx_level]
	if ngx and ngx.log and ngx_level then
		ngx.log(ngx_level, line)
	else
		io.stderr:write(level.label .. " " .. line .. "\n")
	end
end

--- Build a logger bound to a subsystem name.
-- @tparam string tag subsystem name, e.g. "feed_scheduler"
-- @treturn table logger exposing `error`, `warn` and `notice`
function M.tag(tag)
	local logger = {}
	for name, level in pairs(LEVELS) do
		logger[name] = function(msg)
			emit(level, tag, msg)
		end
	end
	return logger
end

return M

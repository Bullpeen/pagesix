--- Map a time-window keyword (hour/day/week/month/year) to a UTC datetime
--- cutoff string, for filtering listings (e.g. top?t=week).
-- @module utils.timewindow

local windows = {
	hour = 3600,
	day = 86400,
	week = 604800,
	month = 2592000,
	year = 31536000,
}

--- @tparam string t window keyword
-- @treturn string|nil cutoff datetime ("YYYY-MM-DD HH:MM:SS"), or nil for all-time
return function(t)
	local secs = windows[t]
	if not secs then
		return nil
	end
	return os.date("!%Y-%m-%d %H:%M:%S", os.time() - secs)
end

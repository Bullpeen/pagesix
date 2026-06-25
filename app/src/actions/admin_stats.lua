--- Admin Control Panel: site-wide statistics + graphs.
-- @module action.admin_stats

local Stats = require("src.utils.stats")
local chart = require("src.utils.chart")
local admin_guard = require("src.utils.admin_guard")

-- Pull one numeric column out of an activity series into a plain array.
local function series(points, key)
	local v = {}
	for i, p in ipairs(points) do
		v[i] = p[key]
	end
	return v
end

return {
	before = function(self)
		local denied = admin_guard(self)
		if denied then
			return denied
		end

		local days = 30
		local activity = Stats.activity(days)
		self.days = days
		self.totals = Stats.totals()
		self.range = {
			from = activity[1] and activity[1].day,
			to = activity[#activity] and activity[#activity].day,
		}

		self.charts = {
			posts = chart.vbars(series(activity, "posts"), { title = "Posts per day" }),
			comments = chart.vbars(series(activity, "comments"), { title = "Comments per day" }),
			signups = chart.vbars(series(activity, "signups"), { title = "Signups per day" }),
		}

		local items = {}
		for _, s in ipairs(Stats.top_subreddits(10)) do
			items[#items + 1] = { label = s.name, value = tonumber(s.posts) or 0 }
		end
		self.charts.top_subreddits = chart.hbars(items, { title = "Top subreddits by posts" })
	end,

	GET = function(self)
		return { render = "admin.stats" }
	end,
}

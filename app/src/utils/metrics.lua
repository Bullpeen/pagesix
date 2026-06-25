--- Prometheus text-exposition metrics for the /metrics endpoint.
-- @module utils.metrics
--
-- Emits the v0.0.4 text format Prometheus scrapes. Content gauges come straight
-- from utils.stats (always available, including under the test harness). HTTP
-- request counts are accumulated in the cross-worker `metrics` shared dict
-- (nginx.conf) by `observe()`, called from app.lua's after_dispatch; when no
-- shared dict is present (the busted suite, which has no nginx) those counters
-- are simply omitted.

local Stats = require("src.utils.stats")

local M = {}

local CLASSES = { "1xx", "2xx", "3xx", "4xx", "5xx" }

-- The shared dict, or nil outside OpenResty (tests / CLI).
local function dict()
	return ngx and ngx.shared and ngx.shared.metrics or nil
end

--- Record a handled request's status class. No-op without the shared dict.
-- @tparam number status HTTP status code
function M.observe(status)
	local d = dict()
	if not d then
		return
	end
	local class = math.floor((tonumber(status) or 0) / 100) .. "xx"
	pcall(d.incr, d, "req:" .. class, 1, 0)
end

-- Per-status-class request totals from the shared dict, or nil if unavailable.
function M.http_requests()
	local d = dict()
	if not d then
		return nil
	end
	local out, any = {}, false
	for _, c in ipairs(CLASSES) do
		local n = d:get("req:" .. c)
		if n then
			out[c] = n
			any = true
		end
	end
	return any and out or nil
end

--- Render the full exposition document.
-- @treturn string
function M.render()
	local t = Stats.totals()
	local out = {}

	local function gauge(name, help, value)
		out[#out + 1] = "# HELP " .. name .. " " .. help
		out[#out + 1] = "# TYPE " .. name .. " gauge"
		out[#out + 1] = name .. " " .. (tonumber(value) or 0)
	end

	gauge("pagesix_up", "1 if the app is serving.", 1)
	gauge("pagesix_users", "Registered users.", t.users)
	gauge("pagesix_subreddits", "Subreddits (communities).", t.subreddits)
	gauge("pagesix_posts", "Live (non-deleted) posts.", t.posts)
	gauge("pagesix_comments", "Live (non-deleted) comments.", t.comments)
	gauge("pagesix_votes", "Votes cast.", t.votes)
	gauge("pagesix_posts_pending", "Posts awaiting moderator approval.", t.pending_posts)
	gauge("pagesix_comments_pending", "Comments awaiting moderator approval.", t.pending_comments)

	local reqs = M.http_requests()
	if reqs then
		out[#out + 1] = "# HELP pagesix_http_requests_total Requests handled, by status class."
		out[#out + 1] = "# TYPE pagesix_http_requests_total counter"
		for _, c in ipairs(CLASSES) do
			if reqs[c] then
				out[#out + 1] = ('pagesix_http_requests_total{status="%s"} %d'):format(c, reqs[c])
			end
		end
	end

	out[#out + 1] = "" -- trailing newline
	return table.concat(out, "\n")
end

return M

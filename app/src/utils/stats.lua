--- Site- and subreddit-level statistics for the admin/mod dashboards, the
--- Prometheus /metrics exporter, and the /health check.
-- @module utils.stats
--
-- All read-side aggregation: site/sub totals, a padded daily-activity series
-- (posts/comments/signups) sourced from the `v_daily_activity` SQL view
-- (migration [110]), and "top" leaderboards. Nothing here mutates state.

local db = require("lapis.db")

local Stats = {}

-- COUNT(*) over a trusted table-expression constant, with optional bound params.
local function count(from, ...)
	return tonumber(db.select("COUNT(*) AS c FROM " .. from, ...)[1].c) or 0
end

-- Clamp a requested day-span to a sane window (default 30, max 365).
local function clamp_days(days)
	return math.max(1, math.min(365, math.floor(tonumber(days) or 30)))
end

-- Expand sparse {day = ...} rows into a continuous series ending today (UTC),
-- zero-filling missing days so charts don't have gaps. `keys` are the numeric
-- columns to carry across (e.g. {"posts", "comments"}).
local function pad_series(rows, days, keys)
	local by_day = {}
	for _, r in ipairs(rows) do
		by_day[r.day] = r
	end
	local out = {}
	local now = os.time()
	for i = days - 1, 0, -1 do
		local day = os.date("!%Y-%m-%d", now - i * 86400)
		local src = by_day[day]
		local point = { day = day }
		for _, k in ipairs(keys) do
			point[k] = tonumber(src and src[k]) or 0
		end
		out[#out + 1] = point
	end
	return out
end

--- Site-wide totals (live counts, excluding soft-deleted content).
-- @treturn table
function Stats.totals()
	return {
		users = count("users"),
		subreddits = count("forum WHERE deleted_at IS NULL"),
		posts = count("posts WHERE deleted = 0"),
		comments = count("comments WHERE deleted = 0"),
		votes = count("votes"),
		pending_posts = count("posts WHERE approved = 0 AND deleted = 0"),
		pending_comments = count("comments WHERE approved = 0 AND deleted = 0"),
		admins = count("site_roles WHERE role = 'admin'"),
	}
end

--- Daily site activity for the last `days` days (newest last), zero-padded.
-- Reads the `v_daily_activity` view. Each point: { day, posts, comments, signups }.
-- @tparam[opt=30] number days
-- @treturn table
function Stats.activity(days)
	days = clamp_days(days)
	local since = os.date("!%Y-%m-%d", os.time() - (days - 1) * 86400)
	local rows = db.select(
		"day, posts, comments, signups FROM v_daily_activity WHERE day >= ? ORDER BY day",
		since
	)
	return pad_series(rows, days, { "posts", "comments", "signups" })
end

--- Subreddits ranked by live post count.
-- @tparam[opt=10] number limit
-- @treturn table array of { name, posts }
function Stats.top_subreddits(limit)
	limit = math.max(1, math.min(50, math.floor(tonumber(limit) or 10)))
	return db.select(
		[[s.name, COUNT(p.id) AS posts
			FROM forum s
			LEFT JOIN posts p ON p.sub_id = s.id AND p.deleted = 0
			WHERE s.deleted_at IS NULL
			GROUP BY s.id
			ORDER BY posts DESC, s.name
			LIMIT ?]],
		limit
	)
end

--- Live totals for a single subreddit.
-- @tparam number sub_id
-- @treturn table
function Stats.sub_totals(sub_id)
	sub_id = tonumber(sub_id)
	return {
		posts = count("posts WHERE sub_id = ? AND deleted = 0", sub_id),
		comments = count(
			[[comments c JOIN posts p ON c.post_id = p.id
				WHERE p.sub_id = ? AND c.deleted = 0]],
			sub_id
		),
		subscribers = count("subscriptions WHERE subreddit_id = ?", sub_id),
		pending = count("posts WHERE sub_id = ? AND approved = 0 AND deleted = 0", sub_id),
	}
end

--- Daily activity (posts + comments) for one subreddit, zero-padded. The global
-- view carries no sub filter, so this aggregates directly.
-- @tparam number sub_id
-- @tparam[opt=30] number days
-- @treturn table array of { day, posts, comments }
function Stats.for_sub(sub_id, days)
	sub_id = tonumber(sub_id)
	days = clamp_days(days)
	local since = os.date("!%Y-%m-%d", os.time() - (days - 1) * 86400)
	local rows = db.select(
		[[day,
			SUM(CASE WHEN kind = 'post'    THEN 1 ELSE 0 END) AS posts,
			SUM(CASE WHEN kind = 'comment' THEN 1 ELSE 0 END) AS comments
			FROM (
				SELECT date(created_at) AS day, 'post' AS kind
					FROM posts WHERE sub_id = ? AND deleted = 0
				UNION ALL
				SELECT date(c.created_at) AS day, 'comment' AS kind
					FROM comments c JOIN posts p ON c.post_id = p.id
					WHERE p.sub_id = ? AND c.deleted = 0
			)
			WHERE day >= ?
			GROUP BY day
			ORDER BY day]],
		sub_id,
		sub_id,
		since
	)
	return pad_series(rows, days, { "posts", "comments" })
end

--- Top posters in a subreddit by live post count.
-- @tparam number sub_id
-- @tparam[opt=10] number limit
-- @treturn table array of { name, posts }
function Stats.top_contributors(sub_id, limit)
	limit = math.max(1, math.min(50, math.floor(tonumber(limit) or 10)))
	return db.select(
		[[u.user_name AS name, COUNT(p.id) AS posts
			FROM posts p
			JOIN users u ON p.user_id = u.id
			WHERE p.sub_id = ? AND p.deleted = 0
			GROUP BY u.id
			ORDER BY posts DESC, u.user_name
			LIMIT ?]],
		tonumber(sub_id),
		limit
	)
end

return Stats

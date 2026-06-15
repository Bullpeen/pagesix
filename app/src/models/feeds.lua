--- RSS/Atom feeds attached to a subreddit (source for the live importer).
-- @module models.feeds

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Feeds = Model:extend("feeds", {
	timestamp = true,
	relations = {
		{ "subreddit", belongs_to = "Forum", key = "sub_id" },
	},
})

--- Attach a feed URL to a subreddit (idempotent on the (sub_id, url) pair).
function Feeds:add(sub_id, url)
	local existing = self:find({ sub_id = sub_id, url = url })
	if existing then
		return existing
	end
	return (self:create({ sub_id = sub_id, url = url }))
end

--- Enabled feeds for a subreddit, oldest first.
function Feeds:for_subreddit(sub_id)
	return self:select("WHERE sub_id = ? AND enabled = 1 ORDER BY id", sub_id)
end

--- Every feed for a subreddit (enabled and disabled), oldest first. Drives the
-- mod feed-management page, which shows disabled feeds too.
function Feeds:list(sub_id)
	return self:select("WHERE sub_id = ? ORDER BY id", sub_id)
end

--- Delete a feed, scoped to its subreddit so a mod can only remove their own
-- sub's feeds. Returns the removed row (for logging) or nil if not found.
function Feeds:remove(sub_id, feed_id)
	local feed = self:find({ id = tonumber(feed_id), sub_id = tonumber(sub_id) })
	if not feed then
		return nil
	end
	feed:delete()
	return feed
end

--- Enable/disable a feed (the scheduler only fetches enabled feeds), scoped to
-- its subreddit. Returns the updated row or nil if not found.
function Feeds:set_enabled(sub_id, feed_id, enabled)
	local feed = self:find({ id = tonumber(feed_id), sub_id = tonumber(sub_id) })
	if not feed then
		return nil
	end
	feed:update({ enabled = enabled and 1 or 0 })
	return feed
end

--- Enabled feeds (across every subreddit) that are due for a refresh now.
-- Applies exponential backoff on consecutive failures so the scheduler stops
-- hammering dead feeds: a healthy feed is refetched once `base_interval`
-- seconds have elapsed; a feed with N failures waits
-- `base_interval * min(2^N, 64)`. Never-fetched feeds are always due and sort
-- first. `last_fetched_at` is a UTC `db.format_date()` string, so SQLite's
-- `strftime('%s', ...)` gives the right epoch delta against `'now'`.
function Feeds:due(base_interval)
	base_interval = tonumber(base_interval) or 900
	return self:select(
		[[WHERE enabled = 1 AND (
			last_fetched_at IS NULL
			OR (strftime('%s', 'now') - strftime('%s', last_fetched_at))
			   >= ? * min((1 << min(failure_count, 6)), 64)
		) ORDER BY last_fetched_at IS NOT NULL, last_fetched_at]],
		base_interval
	)
end

-- Case-insensitive header lookup (luasocket lowercases keys; resty.http uses a
-- case-insensitive metatable, but normalize anyway for the manual/CLI path).
local function header(headers, name)
	if type(headers) ~= "table" then
		return nil
	end
	return headers[name] or headers[name:lower()] or headers[name:upper()]
end

--- Conditional-GET request headers for a feed (empty when we have no cached
-- validators yet). Sent on the next fetch so an unchanged feed answers 304.
function Feeds:conditional_headers(feed)
	local h = {}
	if feed.etag and feed.etag ~= "" then
		h["If-None-Match"] = feed.etag
	end
	if feed.last_modified and feed.last_modified ~= "" then
		h["If-Modified-Since"] = feed.last_modified
	end
	return h
end

--- Record a fetch outcome: stamp last_fetched_at/status, reset or bump the
-- consecutive failure count (so the scheduler can back off dead feeds), and on
-- success cache the response's ETag / Last-Modified for the next conditional GET.
function Feeds:record_result(feed, ok, status, headers)
	local fields = {
		last_fetched_at = db.format_date(),
		last_status = tostring(status),
		failure_count = ok and 0 or (tonumber(feed.failure_count) or 0) + 1,
	}
	if ok then
		local etag = header(headers, "ETag")
		local last_modified = header(headers, "Last-Modified")
		if etag then
			fields.etag = etag
		end
		if last_modified then
			fields.last_modified = last_modified
		end
	end
	feed:update(fields)
end

--- The system account that owns imported posts. Created on demand with an
-- unusable (bcrypt-but-random) password so it can never be logged into.
function Feeds:bot()
	local Users = require("models.users")
	local bot = Users:find({ user_name = "rss_bot" })
	if bot then
		return bot
	end
	local Password = require("src.utils.password")
	return (
		Users:create({
			user_name = "rss_bot",
			user_email = "rss_bot@localhost",
			user_pass = Password.hash("import-bot-" .. tostring(os.time()) .. tostring(os.clock())),
		})
	)
end

return Feeds

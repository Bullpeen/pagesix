--- Live RSS/Atom import: fetch a feed, parse it, and create posts for new
--- entries (deduped on posts.external_guid).
-- @module utils.feed_import
--
-- `fetch` is a module field so tests can stub the network. The fetch is blocking
-- (luasocket / luasec) -- fine for a manual or cron-driven refresh; an
-- in-process ngx.timer scheduler (non-blocking lua-resty-http) is a follow-up.

local M = {}

--- Blocking HTTP(S) GET. Overridable in tests via `feed_import.fetch`.
-- @treturn string|nil body
-- @treturn number|string status (HTTP code, or an error string)
function M.fetch(url)
	local is_https = url:match("^https://") ~= nil
	local ok_https, https = pcall(require, "ssl.https")
	local http = require("socket.http")
	http.TIMEOUT = 10
	local client = (is_https and ok_https) and https or http
	if client.TIMEOUT == nil then
		client.TIMEOUT = 10
	end
	local body, status = client.request(url)
	return body, status
end

--- Create posts for entries not already imported into this subreddit.
-- @treturn number imported
-- @treturn number skipped (already present, or rejected by a model constraint)
function M.import_entries(sub_id, user_id, entries)
	local Posts = require("src.models.posts")
	local media = require("src.utils.media")
	local db = require("lapis.db")

	local imported, skipped = 0, 0
	for _, e in ipairs(entries) do
		local guid = e.guid or e.link
		local exists =
			db.select("1 FROM posts WHERE sub_id = ? AND external_guid = ? LIMIT 1", sub_id, guid)
		if exists[1] then
			skipped = skipped + 1
		else
			local post = Posts:create({
				sub_id = sub_id,
				user_id = user_id,
				title = e.title,
				url = e.link,
				external_guid = guid,
				thumbnail = media.thumbnail_for(e.link),
			})
			if post then
				imported = imported + 1
			else
				skipped = skipped + 1
			end
		end
	end
	return imported, skipped
end

--- Fetch + parse + import a single feed row, recording the fetch outcome.
-- @tparam table feed a feeds row
-- @tparam[opt] function fetch_fn override the fetcher (tests)
-- @treturn number imported
function M.refresh_feed(feed, fetch_fn)
	local Feeds = require("src.models.feeds")
	local parse = require("src.utils.feed_parse")
	local fetch = fetch_fn or M.fetch

	local bot = Feeds:bot()
	if not bot then
		return 0
	end

	local body, status = fetch(feed.url)
	local ok = type(status) == "number" and status >= 200 and status < 400 and body ~= nil
	if not ok then
		Feeds:record_result(feed, false, status)
		return 0
	end

	local imported = M.import_entries(tonumber(feed.sub_id), bot.id, parse(body))
	Feeds:record_result(feed, true, status)
	return imported
end

--- Refresh every enabled feed for a subreddit.
-- @treturn number total imported across the sub's feeds
function M.refresh_subreddit(sub_id, fetch_fn)
	local Feeds = require("src.models.feeds")
	local total = 0
	for _, feed in ipairs(Feeds:for_subreddit(sub_id)) do
		total = total + (M.refresh_feed(feed, fetch_fn) or 0)
	end
	return total
end

return M

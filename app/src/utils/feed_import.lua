--- Live RSS/Atom import: fetch a feed, parse it, and create posts for new
--- entries (deduped on posts.external_guid).
-- @module utils.feed_import
--
-- `fetch` is a module field so tests can stub the network. Inside OpenResty
-- (the in-process scheduler's ngx.timer) it uses the non-blocking resty.http
-- client so a slow feed never stalls the worker; elsewhere (the manual mod
-- trigger, a CLI run, tests) it falls back to blocking luasocket / luasec.

local M = {}

--- HTTP(S) GET. Non-blocking (resty.http) under OpenResty, blocking
-- (luasocket/luasec) otherwise. Overridable in tests via `feed_import.fetch`.
-- @tparam string url
-- @tparam[opt] table headers extra request headers (conditional GET)
-- @treturn string|nil body
-- @treturn number|string status (HTTP code, or an error string)
-- @treturn table|nil response headers
function M.fetch(url, headers)
	-- Non-blocking path: resty.http via cosockets (works inside ngx.timer).
	local ok_resty, resty_http = pcall(require, "resty.http")
	if ngx and ok_resty then
		local httpc = resty_http.new()
		httpc:set_timeout(10000)
		local res, err = httpc:request_uri(url, { headers = headers })
		if not res then
			return nil, err
		end
		return res.body, res.status, res.headers
	end

	-- Blocking fallback. Use the generic request form so we can pass request
	-- headers and read the response status + headers back.
	local is_https = url:match("^https://") ~= nil
	local ok_https, https = pcall(require, "ssl.https")
	local http = require("socket.http")
	local ltn12 = require("ltn12")
	http.TIMEOUT = 10
	local client = (is_https and ok_https) and https or http
	if client.TIMEOUT == nil then
		client.TIMEOUT = 10
	end
	local chunks = {}
	local _, status, resp_headers = client.request({
		url = url,
		headers = headers,
		sink = ltn12.sink.table(chunks),
	})
	return table.concat(chunks), status, resp_headers
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
-- Sends the feed's cached conditional-GET validators; a 304 (unchanged) counts
-- as a success and imports nothing.
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

	local body, status, headers = fetch(feed.url, Feeds:conditional_headers(feed))

	-- 304 Not Modified: nothing changed since our last fetch -- a success with
	-- no new entries (and we keep the cached validators).
	if tonumber(status) == 304 then
		Feeds:record_result(feed, true, status, headers)
		return 0
	end

	local code = tonumber(status)
	local ok = code ~= nil and code >= 200 and code < 400 and body ~= nil
	if not ok then
		Feeds:record_result(feed, false, status)
		return 0
	end

	local imported = M.import_entries(tonumber(feed.sub_id), bot.id, parse(body))
	Feeds:record_result(feed, true, status, headers)
	return imported
end

--- Refresh every enabled feed for a subreddit (the manual mod trigger refreshes
-- all of a sub's feeds regardless of the scheduler's due/backoff window).
-- @treturn number total imported across the sub's feeds
function M.refresh_subreddit(sub_id, fetch_fn)
	local Feeds = require("src.models.feeds")
	local total = 0
	for _, feed in ipairs(Feeds:for_subreddit(sub_id)) do
		total = total + (M.refresh_feed(feed, fetch_fn) or 0)
	end
	return total
end

--- Refresh every feed (across all subreddits) that is due now. Drives the
-- in-process scheduler (see utils.feed_scheduler).
-- @tparam[opt] number base_interval min seconds between fetches of a feed
-- @tparam[opt] function fetch_fn override the fetcher (tests)
-- @treturn number total imported
-- @treturn number feeds checked this pass
function M.refresh_all(base_interval, fetch_fn)
	local Feeds = require("src.models.feeds")
	local due = Feeds:due(base_interval)
	local total = 0
	for _, feed in ipairs(due) do
		total = total + (M.refresh_feed(feed, fetch_fn) or 0)
	end
	return total, #due
end

return M

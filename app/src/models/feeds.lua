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

--- Record a fetch outcome: stamp last_fetched_at/status and reset or bump the
-- consecutive failure count (so a future scheduler can back off dead feeds).
function Feeds:record_result(feed, ok, status)
	feed:update({
		last_fetched_at = db.format_date(),
		last_status = tostring(status),
		failure_count = ok and 0 or (tonumber(feed.failure_count) or 0) + 1,
	})
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

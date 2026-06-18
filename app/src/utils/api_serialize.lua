--- Reddit-shaped JSON serialization for the API
-- @module utils.api_serialize
--
-- Turns our model rows into the "Thing" envelopes the Reddit API speaks:
-- `{ kind = "t3", data = { ... } }` for a link, `t1` for a comment, `t2` for
-- an account, `t5` for a subreddit, and `{ kind = "Listing", data = { children
-- = { ... }, after, before, dist } }` for a page of them.
--
-- Two id schemes are exposed per thing:
--   * `id` / `name` -- Reddit's base36 of the row id and its `t?_<id>` fullname,
--     so existing Reddit API clients work unchanged.
--   * `uuid` -- the opaque, stable `public_id` (migration [109]); minted lazily
--     here the first time a row is serialized so old rows backfill on demand.

local db = require("lapis.db")
local uuid = require("src.utils.uuid")

local M = {}

-- Reddit "kind" prefixes. https://www.reddit.com/dev/api/#fullnames
M.KINDS = {
	comment = "t1",
	account = "t2",
	link = "t3",
	message = "t4",
	subreddit = "t5",
}

-- Map a prefix back to the table it identifies, for parse_fullname / /api/info.
local PREFIX_TABLE = {
	t1 = "comments",
	t2 = "users",
	t3 = "posts",
	t5 = "forum",
}

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

--- Encode a non-negative integer as lowercase base36 (Reddit's id alphabet).
-- @tparam number n
-- @treturn string
function M.base36(n)
	n = math.floor(tonumber(n) or 0)
	if n == 0 then
		return "0"
	end
	local out = {}
	while n > 0 do
		local r = n % 36
		out[#out + 1] = DIGITS:sub(r + 1, r + 1)
		n = math.floor(n / 36)
	end
	return string.reverse(table.concat(out))
end

--- Decode a base36 string back to a number, or nil if it isn't valid base36.
-- @tparam string s
-- @treturn number|nil
function M.from_base36(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local n = 0
	for i = 1, #s do
		local d = DIGITS:find(s:sub(i, i):lower(), 1, true)
		if not d then
			return nil
		end
		n = n * 36 + (d - 1)
	end
	return n
end

--- Build a Reddit fullname, e.g. fullname("link", 42) -> "t3_16".
-- @tparam string kind one of M.KINDS' keys
-- @tparam number id
-- @treturn string
function M.fullname(kind, id)
	return M.KINDS[kind] .. "_" .. M.base36(id)
end

--- Split a fullname into the table it points at and the numeric id.
-- parse_fullname("t3_16") -> "posts", 42. Returns nil for anything malformed.
-- @tparam string name
-- @treturn string|nil table_name
-- @treturn number|nil id
function M.parse_fullname(name)
	if type(name) ~= "string" then
		return nil
	end
	local prefix, b36 = name:match("^(t%d)_(%w+)$")
	local tbl = prefix and PREFIX_TABLE[prefix]
	local id = tbl and M.from_base36(b36)
	if not id then
		return nil
	end
	return tbl, id
end

--- The stable `public_id` for a row, minting + persisting one if absent.
-- Many listing projections don't SELECT `public_id`, so a nil on the row does
-- not mean the column is unset -- we re-read it before minting, otherwise we'd
-- clobber the backfilled (stable) value with a fresh one on every serialize.
-- @tparam string table_name
-- @tparam table row a row with `id` (and maybe `public_id`)
-- @treturn string
function M.ensure_public_id(table_name, row)
	if row.public_id and row.public_id ~= "" then
		return row.public_id
	end
	local stored = db.select("public_id FROM " .. table_name .. " WHERE id = ?", tonumber(row.id))
	if stored[1] and stored[1].public_id and stored[1].public_id ~= db.NULL then
		row.public_id = stored[1].public_id
		return row.public_id
	end
	local id = uuid.generate()
	db.update(table_name, { public_id = id }, { id = row.id })
	row.public_id = id
	return id
end

-- 0/1/"0"/"1"/nil -> boolean, for the integer flag columns.
local function bool(v)
	return tonumber(v) == 1
end

local function num(v)
	return tonumber(v) or 0
end

-- Best-effort UTC epoch from a "YYYY-MM-DD HH:MM:SS" stored timestamp. The
-- stored value is SQLite's CURRENT_TIMESTAMP (UTC); os.time treats the fields
-- as local, so subtract the local<->UTC offset to land back on UTC. Returns 0
-- when the timestamp is missing/unparseable.
local function to_epoch(ts)
	if type(ts) ~= "string" then
		return 0
	end
	local y, mo, d, h, mi, s = ts:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
	if not y then
		return 0
	end
	local offset = os.time() - os.time(os.date("!*t"))
	return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s }) + offset
end

--- Serialize a post row as a `t3` link Thing. Accepts the enriched listing rows
-- (author/subreddit/vote aggregates already joined) and falls back to lookups
-- for a bare `Posts:find` row, so single-item endpoints work too.
-- @tparam table p
-- @treturn table
function M.link(p)
	local ups, downs
	if p.upvotes ~= nil or p.downvotes ~= nil then
		ups, downs = num(p.upvotes), num(p.downvotes)
	else
		-- Bare Posts:find row (single-item endpoints): count up/down directly so
		-- the reported score matches the listing path's, not just the net.
		local row = db.select(
			[[SUM(CASE WHEN upvote = 1 THEN 1 ELSE 0 END) AS u,
				SUM(CASE WHEN upvote = 0 THEN 1 ELSE 0 END) AS d
				FROM votes WHERE post_id = ? AND comment_id IS NULL]],
			tonumber(p.id)
		)
		ups, downs = num(row[1] and row[1].u), num(row[1] and row[1].d)
	end

	local subreddit = p.subreddit
	if not subreddit and p.sub_id then
		local sub = require("src.models.forum"):find(p.sub_id)
		subreddit = sub and sub.name
	end

	local author = p.author
	if not author and p.user_id then
		local u = require("models.users"):find(p.user_id)
		author = u and u.user_name
	end

	local num_comments = p.num_comments
	if num_comments == nil then
		local row = db.select("COUNT(*) AS c FROM comments WHERE post_id = ?", tonumber(p.id))
		num_comments = row[1] and row[1].c or 0
	end

	return {
		kind = M.KINDS.link,
		data = {
			id = M.base36(p.id),
			name = M.fullname("link", p.id),
			uuid = M.ensure_public_id("posts", p),
			title = p.title,
			url = p.url,
			permalink = p.permalink or ("/r/" .. tostring(subreddit) .. "/comments/" .. p.id),
			author = author,
			subreddit = subreddit,
			subreddit_name_prefixed = subreddit and ("r/" .. subreddit) or nil,
			domain = p.domain,
			selftext = p.body,
			is_self = bool(p.is_self),
			score = ups - downs,
			ups = ups,
			downs = downs,
			num_comments = num(num_comments),
			over_18 = bool(p.over_18),
			stickied = bool(p.stickied),
			locked = bool(p.locked),
			link_flair_text = p.link_flair,
			edited = bool(p.edited),
			created = p.created_at,
			created_utc = to_epoch(p.created_at),
		},
	}
end

--- Serialize a comment row (a `thread`/`by_user` row) as a `t1` Thing.
-- @tparam table c
-- @treturn table
function M.comment(c)
	local ups = num(c.upvotes)
	local downs = num(c.downvotes)
	return {
		kind = M.KINDS.comment,
		data = {
			id = M.base36(c.id),
			name = M.fullname("comment", c.id),
			uuid = M.ensure_public_id("comments", c),
			body = bool(c.deleted) and "[deleted]" or c.body,
			author = bool(c.deleted) and "[deleted]" or c.author,
			link_id = M.fullname("link", c.post_id),
			parent_id = c.parent_comment_id and M.fullname("comment", c.parent_comment_id)
				or M.fullname("link", c.post_id),
			subreddit = c.subreddit,
			score = ups - downs,
			ups = ups,
			downs = downs,
			is_submitter = bool(c.is_submitter),
			stickied = bool(c.stickied),
			edited = bool(c.edited),
			permalink = c.permalink,
			created = c.created_at,
			created_utc = to_epoch(c.created_at),
			replies = "",
		},
	}
end

--- Serialize a user row as a `t2` account Thing. Following Reddit, `data.name`
-- is the username (the thing's fullname is `t2_<id>`, exposed as `fullname`).
-- @tparam table u
-- @treturn table
function M.account(u)
	local Users = require("models.users")
	return {
		kind = M.KINDS.account,
		data = {
			id = M.base36(u.id),
			name = u.user_name,
			fullname = M.fullname("account", u.id),
			uuid = M.ensure_public_id("users", u),
			total_karma = Users:karma(u.id),
			reputation = num(u.reputation),
			trust_level = Users:trust_level(u.reputation),
			over_18 = bool(u.over_18),
			created = u.created_at,
			created_utc = to_epoch(u.created_at),
		},
	}
end

--- Serialize a subreddit row as a `t5` Thing. Accepts a `forum` row or a
-- listing row (which exposes `subscribers`).
-- @tparam table f
-- @treturn table
function M.subreddit(f)
	local subscribers = f.subscribers
	if subscribers == nil and f.id then
		local row =
			db.select("COUNT(*) AS c FROM subscriptions WHERE subreddit_id = ?", tonumber(f.id))
		subscribers = row[1] and row[1].c or 0
	end
	return {
		kind = M.KINDS.subreddit,
		data = {
			id = f.id and M.base36(f.id) or nil,
			name = f.id and M.fullname("subreddit", f.id) or nil,
			uuid = f.id and M.ensure_public_id("forum", f) or nil,
			display_name = f.name,
			display_name_prefixed = "r/" .. f.name,
			title = f.name,
			public_description = f.description,
			subscribers = num(subscribers),
			over18 = bool(f.nsfw),
			url = "/r/" .. f.name,
			created = f.created_at,
			created_utc = to_epoch(f.created_at),
		},
	}
end

--- Wrap an array of Things in a Listing envelope.
-- @tparam table children array of serialized Things
-- @tparam[opt] table opts { after = fullname|nil, before = fullname|nil }
-- @treturn table
function M.listing(children, opts)
	opts = opts or {}
	return {
		kind = "Listing",
		data = {
			after = opts.after,
			before = opts.before,
			dist = #children,
			children = children,
		},
	}
end

-- Clamp a requested limit to [1, 100] (Reddit's ceiling), default 25.
local function clamp_limit(raw)
	local n = tonumber(raw) or 25
	return math.max(1, math.min(100, math.floor(n)))
end

--- Cursor-paginate an array of listing rows (each with a numeric `.id`) by
-- Reddit `after`/`before` fullnames and `limit`. Returns the page of rows plus
-- the fullnames to use for the next/previous page (nil when at an edge).
-- @tparam table rows ordered rows
-- @tparam table params request params ({ after, before, limit })
-- @tparam string kind the rows' kind ("link" | "comment" | ...) for fullnames
-- @treturn table page rows
-- @treturn string|nil after fullname
-- @treturn string|nil before fullname
function M.paginate(rows, params, kind)
	local limit = clamp_limit(params.limit)

	-- Locate the cursor row by its fullname's numeric id.
	local function index_of(name)
		local _, id = M.parse_fullname(name)
		if not id then
			return nil
		end
		for i, r in ipairs(rows) do
			if tonumber(r.id) == id then
				return i
			end
		end
		return nil
	end

	local start = 1
	local after_idx = params.after and index_of(params.after)
	if after_idx then
		start = after_idx + 1
	elseif params.before then
		local before_idx = index_of(params.before)
		if before_idx then
			start = math.max(1, before_idx - limit)
		end
	end

	local page = {}
	for i = start, math.min(#rows, start + limit - 1) do
		page[#page + 1] = rows[i]
	end

	local last = page[#page]
	local first = page[1]
	local more_after = last and (start + #page - 1) < #rows
	local after = more_after and M.fullname(kind, last.id) or nil
	local before = (start > 1 and first) and M.fullname(kind, first.id) or nil
	return page, after, before
end

return M

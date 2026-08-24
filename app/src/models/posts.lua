--- Posts model
-- @module models.posts

local model = require("lapis.db.model")
local db = require("lapis.db")
local Url = require("src.utils.url")
local Model, enum = model.Model, model.enum

-- We target the 5.1 ABI (LuaJIT/OpenResty), where `unpack` is a global; the
-- `table.unpack` fallback keeps this loadable under 5.2+ as well.
local unpack = unpack or table.unpack -- luacheck: ignore 143

local Posts = Model:extend("posts", {
	timestamp = true,

	constraints = {
		-- Lapis validates the title on create/update; truthy return blocks it.
		title = function(self, value)
			if not value or value == "" then
				return "Title is required"
			end
			if #value > 300 then
				return "Title must be under 300 characters"
			end
		end,
	},

	-- https://leafo.net/lapis/reference/actions.html#request-object-methods/request:url_for/passing-an-object-to-url-for
	-- Build the args for url_for("post", ...) so `url_for(post)` resolves to
	-- /r/<subreddit>/comments/<id>/<title-stub>.
	url_params = function(self, req, ...)
		local Forum = require("src.models.forum")
		local sub = self.sub_id and Forum:find(self.sub_id)

		local stub = (self.title or ""):lower()
		stub = stub:gsub("[^%w]+", "_")
		stub = stub:gsub("^_+", "")
		stub = stub:gsub("_+$", "")

		return "post",
			{
				subreddit = sub and sub.name or "all",
				post_id = self.id,
				title_stub = stub ~= "" and stub or nil,
			},
			...
	end,

	relations = {
		{ "comments", has_many = "Comments" },
		-- The FK column is `sub_id`, not the default `subreddit_id`, so
		-- get_subreddit() needs an explicit key or it always resolves to nil.
		{ "subreddit", belongs_to = "Forum", key = "sub_id" },
		{ "user", belongs_to = "Users" },
		{ "votes", has_many = "Votes" },

		-- { "votes",
		--     has_many="Votes",
		--     where = {sub_id = id},
		--     order = "id desc",
		--     key = "post_id"
		-- },
	},
})

Posts.statuses = enum({
	pending = 1,
	public = 2,
	private = 3,
	locked = 4,
	deleted = 5,
})

--- Create a post, stamping the normalized link `domain` from its url.
-- A single hook for every creation path (submit, crosspost, RSS import, seed)
-- so the stored host stays consistent; self/relative posts (no host) store
-- NULL. A url is set once at creation and never edited, so this is the only
-- place the domain needs computing. Returns whatever Model:create returns
-- (the row, or nil + error).
-- @tparam table values column values, including the post `url`
-- @return table|nil, string|nil
function Posts:create(values, ...)
	if type(values) == "table" and values.domain == nil then
		local host = Url.domain(values.url)
		values.domain = host ~= "" and host or nil
	end
	return Model.create(self, values, ...)
end

-- New rows arrive with their external id already set (see utils/public_id).
require("src.utils.public_id").mint_on_create(Posts)

--- Get posts in a thread
-- @tparam number post_id Post ID
-- @tparam number offset Offset
-- @tparam number limit Limit
-- @treturn table posts
-- function Posts:get_top_level_comments(post_id, offset, limit)
-- 	local post = self:find(post_id)
-- 	return post:get_comments(offset, limit)
-- end

-- Ranking expressed as SQL, so the database can order and slice instead of
-- handing every matching row to Lua. Each expression is *order-equivalent* to
-- the comparator `utils/sort` applies in memory:
--
--   * `best` / `top` / `rising` are the same arithmetic.
--   * `hot` drops the outer `log()`: log is monotonically increasing and its
--     argument here is always > 0, so the ordering is identical without it.
--   * `controversial` is Reddit's `(up + down) ^ (min/max)`, zero unless both
--     sides voted -- SQLite's `pow()` (math functions, 3.35+).
--
-- ORDER BY reads the `upvotes`/`downvotes` output aliases rather than repeating
-- the correlated subqueries that produce them.
local ORDER_BY = {
	new = "a.created_at DESC",
	best = "upvotes DESC",
	top = "(upvotes - downvotes) DESC",
	rising = [[((upvotes - downvotes)
		/ MAX((strftime('%s', 'now') - strftime('%s', a.created_at)) / 3600.0, 1)) DESC]],
	hot = "(ABS(upvotes - downvotes) + strftime('%s', a.created_at) / 45000.0) DESC",
	controversial = [[(CASE WHEN upvotes > 0 AND downvotes > 0
		THEN POW(upvotes + downvotes, (MIN(upvotes, downvotes) * 1.0) / MAX(upvotes, downvotes))
		ELSE 0 END) DESC]],
}

--- Sorts whose ordering key is stable enough to address with a cursor.
--
-- Only `new`: its key is `(created_at, id)`, which never changes once a post is
-- written. Every other sort ranks on live vote counts, so a row's position moves
-- between requests and a cursor into it could not be exact however it was
-- implemented -- those page by window instead (see utils/api_serialize).
Posts.KEYSET_SORTS = { new = true }
local KEYSET_SORTS = Posts.KEYSET_SORTS

--- Listing rows for a frontpage / subreddit, with the vote and comment
-- aggregates the templates expect.
--
-- Ordering and slicing happen in SQL. Passing `limit` keeps the query bounded;
-- without it every matching row is returned, which is what the callers that
-- render a whole small set (e.g. `/saved`) still want.
--
-- @tparam[opt] number|table filters a subreddit id (legacy), or a table of:
--   `sub_id`, `user_id`, `since`, `exclude_hidden_for`, `saved_for`, `domain`,
--   `tag` to restrict the listing; `sort` (a key of ORDER_BY, default "new"),
--   `sticky_first` to pin stickied posts, and `limit`/`offset` to page.
-- @treturn table array of plain post rows
function Posts:get_listing(filters)
	-- Backwards compatible: a bare number means sub_id.
	if type(filters) == "number" then
		filters = { sub_id = filters }
	end
	filters = filters or {}

	local query = [[
		a.id, a.public_id, a.title, a.url, a.body, a.is_self, a.over_18, a.locked, a.sub_id, a.thumbnail, a.domain,
			a.link_flair, a.stickied, a.comments_locked, a.is_question, a.accepted_comment_id,
			a.created_at AS age, a.created_at,
			c.user_name AS author,
			s.name AS subreddit,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 1) AS upvotes,
			(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 0) AS downvotes,
			(SELECT COUNT(*) FROM comments d WHERE d.post_id = a.id) AS num_comments
		FROM posts a
		INNER JOIN users c ON a.user_id = c.id
		INNER JOIN forum s ON a.sub_id = s.id
		WHERE a.locked = 0 AND a.deleted = 0 AND a.approved = 1]]

	-- Filters are appended as bound fragments: no request value is ever
	-- interpolated into the SQL text.
	local params = {}
	local function restrict(sql, value)
		query = query .. " AND " .. sql
		params[#params + 1] = value
	end

	if filters.sub_id then
		restrict("a.sub_id = ?", tonumber(filters.sub_id))
	end
	if filters.user_id then
		restrict("a.user_id = ?", tonumber(filters.user_id))
	end
	if filters.since then
		restrict("a.created_at >= ?", filters.since)
	end
	if filters.exclude_hidden_for then
		restrict(
			"a.id NOT IN (SELECT post_id FROM hidden_posts WHERE user_id = ?)",
			tonumber(filters.exclude_hidden_for)
		)
	end
	if filters.saved_for then
		restrict(
			"a.id IN (SELECT post_id FROM saved_posts WHERE user_id = ?)",
			tonumber(filters.saved_for)
		)
	end
	if filters.domain then
		-- Exact match on the stored, normalized host (migration [108]) -- not a
		-- substring of the raw url, which conflated notexample.com / ?ref=host.
		restrict("a.domain = ?", filters.domain)
	end
	if filters.tag then
		restrict(
			"a.id IN (SELECT pt.post_id FROM post_tags pt"
				.. " INNER JOIN tags t ON pt.tag_id = t.id WHERE t.name = ?)",
			filters.tag
		)
	end

	-- Keyset cursors, for the sorts whose key is stable (see KEYSET_SORTS).
	-- Comparing the whole key as a row value -- `(created_at, id) < (...)` --
	-- expresses "strictly past that row in this order" in one shot, including
	-- the tiebreaker. A cursor id that no longer exists makes the subquery NULL,
	-- so the comparison is NULL, so no rows come back: a stale cursor reads as
	-- "nothing after this", which is what the API wants.
	local reversed = false
	if filters.after_id or filters.before_id then
		assert(
			KEYSET_SORTS[filters.sort or "new"],
			"keyset cursors need a stable sort key; '" .. tostring(filters.sort) .. "' has none"
		)
		if filters.after_id then
			restrict(
				"(a.created_at, a.id) < (SELECT created_at, id FROM posts WHERE id = ?)",
				tonumber(filters.after_id)
			)
		else
			-- Walking backwards: take the rows *above* the cursor in ascending
			-- order (so LIMIT keeps the ones nearest it) and flip them back.
			restrict(
				"(a.created_at, a.id) > (SELECT created_at, id FROM posts WHERE id = ?)",
				tonumber(filters.before_id)
			)
			reversed = true
		end
	end

	-- `a.id DESC` breaks ties deterministically. Without it, equal-ranked rows
	-- could swap between requests and LIMIT/OFFSET paging would repeat or skip
	-- them -- the in-memory `table.sort` this replaces was likewise unstable.
	local order = ORDER_BY[filters.sort] or ORDER_BY.new
	if reversed then
		order = "a.created_at ASC"
	end
	if filters.sticky_first then
		order = "a.stickied DESC, " .. order
	end
	query = query .. " ORDER BY " .. order .. (reversed and ", a.id ASC" or ", a.id DESC")

	if filters.limit then
		query = query .. " LIMIT ? OFFSET ?"
		params[#params + 1] = tonumber(filters.limit)
		params[#params + 1] = tonumber(filters.offset) or 0
	end

	local rows = db.select(query, unpack(params))

	if reversed then
		-- Hand the caller the same descending order every other path returns.
		for i = 1, math.floor(#rows / 2) do
			rows[i], rows[#rows - i + 1] = rows[#rows - i + 1], rows[i]
		end
	end

	for _, post in ipairs(rows) do
		post.permalink = "/r/" .. post.subreddit .. "/comments/" .. post.id
		-- Prefer the stored host; fall back to parsing for any pre-backfill row.
		post.domain = post.domain or Url.domain(post.url)
	end

	return rows
end

-- Shared projection for search results: the same vote/comment aggregates and
-- enrichable columns get_listing returns, including the stored `domain`.
local SEARCH_SELECT = [[
	a.id, a.public_id, a.title, a.url, a.body, a.is_self, a.over_18, a.locked, a.sub_id, a.thumbnail, a.domain,
		a.link_flair,
		a.created_at AS age, a.created_at,
		c.user_name AS author,
		s.name AS subreddit,
		(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 1) AS upvotes,
		(SELECT COUNT(*) FROM votes v WHERE v.post_id = a.id AND v.comment_id IS NULL AND v.upvote = 0) AS downvotes,
		(SELECT COUNT(*) FROM comments d WHERE d.post_id = a.id) AS num_comments ]]

local function enrich(rows)
	for _, post in ipairs(rows) do
		post.permalink = "/r/" .. post.subreddit .. "/comments/" .. post.id
		post.domain = post.domain or Url.domain(post.url)
	end
	return rows
end

-- A title word must score at least this Jaro-Winkler similarity against a query
-- word to count as a fuzzy hit. High enough that only near-misses (typos) match,
-- not loosely-related words.
local FUZZY_WORD_THRESHOLD = 0.85

--- Typo-tolerant fallback over post titles, used only when FTS5 found nothing
-- and the sqlean `fuzzy`/`regexp` extensions are loaded. Compares words, not
-- whole strings: each title is normalized (regexp_replace strips punctuation)
-- and split into words by a recursive CTE, the query is split into words (a
-- VALUES list), and a post matches when some title word is Jaro-Winkler-close to
-- some query word -- so "programing" still finds "...programming...". This is
-- what makes it work on multi-word titles. It scans every post, so it is gated
-- behind an otherwise-empty FTS result (a rare path) and capped at 50 rows.
-- @tparam string query
-- @treturn table array of post rows (unenriched)
local function fuzzy_title_search(query)
	local terms = {}
	for word in tostring(query):lower():gmatch("%w+") do
		terms[#terms + 1] = "(" .. db.escape_literal(word) .. ")"
	end
	if #terms == 0 then
		return {}
	end

	return db.select(SEARCH_SELECT .. [[
		FROM posts a
		INNER JOIN users c ON a.user_id = c.id
		INNER JOIN forum s ON a.sub_id = s.id
		INNER JOIN (
			WITH RECURSIVE titlewords(id, word, rest) AS (
				SELECT p.id, '', regexp_replace(lower(p.title), '[^a-z0-9]+', ' ') || ' '
					FROM posts p WHERE p.deleted = 0 AND p.approved = 1
				UNION ALL
				SELECT id, substr(rest, 1, instr(rest, ' ') - 1), substr(rest, instr(rest, ' ') + 1)
					FROM titlewords WHERE rest != ''
			),
			qwords(term) AS (VALUES ]] .. table.concat(terms, ", ") .. [[)
			SELECT tw.id AS post_id, max(jaro_winkler(tw.word, q.term)) AS score
				FROM titlewords tw, qwords q
				WHERE tw.word != ''
				GROUP BY tw.id
				HAVING max(jaro_winkler(tw.word, q.term)) >= ]] .. FUZZY_WORD_THRESHOLD .. [[
		) m ON m.post_id = a.id
		ORDER BY m.score DESC, a.created_at DESC
		LIMIT 50]])
end

--- Full-text search over post titles/bodies via the FTS5 index (migration [7]),
-- ordered by relevance. When FTS returns nothing and the sqlean extensions are
-- loaded, retry with the word-level fuzzy pass above so a typo'd query
-- ("programing") can still surface a near match. FTS stays the default and the
-- fuzzy step only widens an otherwise-empty result, so behaviour is unchanged
-- without the extensions. Returns the same enriched rows as get_listing.
-- @tparam string query the user's search text
-- @treturn table array of post rows
function Posts:search(query)
	if not query or query == "" then
		return {}
	end
	-- Wrap as a quoted FTS5 phrase so arbitrary user input can't break the
	-- MATCH syntax (double-quotes are escaped by doubling).
	local phrase = '"' .. tostring(query):gsub('"', '""') .. '"'

	local rows = db.select(SEARCH_SELECT .. [[
		FROM posts_fts f
		INNER JOIN posts a ON a.id = f.rowid
		INNER JOIN users c ON a.user_id = c.id
		INNER JOIN forum s ON a.sub_id = s.id
		WHERE posts_fts MATCH ? AND a.deleted = 0 AND a.approved = 1
		ORDER BY rank
		LIMIT 50]], phrase)

	if #rows == 0 and require("src.utils.sqlite_ext").load() then
		rows = fuzzy_title_search(query)
	end

	return enrich(rows)
end

--- Posts in a subreddit awaiting moderator approval (the queue), newest first.
-- @tparam number sub_id
-- @treturn table array of post rows with the author's name
function Posts:pending_for_sub(sub_id)
	return db.select(
		[[
		a.id, a.title, a.url, a.body, a.created_at, u.user_name AS author
			FROM posts a
			INNER JOIN users u ON a.user_id = u.id
			WHERE a.sub_id = ? AND a.approved = 0 AND a.deleted = 0
			ORDER BY a.created_at DESC]],
		tonumber(sub_id)
	)
end

return Posts

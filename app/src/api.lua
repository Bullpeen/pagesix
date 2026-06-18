--- JSON API
-- @module src.api
--
-- A Reddit-flavoured JSON API over the same models the web app uses. Every
-- endpoint returns "Thing"/"Listing" envelopes (see utils.api_serialize) and
-- reuses the existing models for all reads and writes -- nothing here re-queries
-- by hand where a model method already does it.
--
-- Routing: everything is namespaced under `/api/` so it never collides with the
-- HTML app's `/(:sort)` homepage catch-all or its `/r/...` routes. (The old stub
-- mirrored Reddit's bare paths like `/hot` and `/r/:sub/about`, which would have
-- shadowed -- or been shadowed by -- the live HTML routes.)
--
-- Auth + CSRF: write endpoints run behind the same session login and the global
-- CSRF before_filter as the web forms (app.lua), which accepts the token from an
-- `X-Csrf-Token` header as well as a `csrf_token` param. A future phase can add
-- OAuth bearer tokens; for now an API client authenticates with the session
-- cookie + CSRF token, exactly like the browser.

local db = require("lapis.db")
local S = require("src.utils.api_serialize")
local Sort = require("src.utils.sort")
local timewindow = require("src.utils.timewindow")

local Users = require("models.users")
local Posts = require("src.models.posts")
local Comments = require("models.comments")
local Forum = require("src.models.forum")
local Votes = require("src.models.votes")
local SavedPosts = require("models.saved_posts")
local HiddenPosts = require("models.hidden_posts")
local Subscriptions = require("models.subscriptions")

-- Flood-control budgets, matching the web submit/comment actions.
local POST_RATE, POST_WINDOW = 10, 600
local COMMENT_RATE, COMMENT_WINDOW = 30, 600

-- Sorts that map to a Sort comparator. "new" is intentionally absent: the
-- listing query already returns rows newest-first, so we leave that order be.
local SORTS = {
	hot = true,
	top = true,
	best = true,
	controversial = true,
	rising = true,
	new = true,
}

-- ---- response helpers --------------------------------------------------------

local function err(status, message)
	return { status = status, json = { error = status, message = message } }
end

-- The logged-in user row, or nil. Mirrors the action auth pattern.
local function current_user(self)
	return self.session.current_user and Users:find({ user_name = self.session.current_user })
		or nil
end

-- ---- listing assembly --------------------------------------------------------

-- Order a fresh listing by the requested sort (default "hot"); "new" keeps the
-- query's created-desc order.
local function sorted_listing(rows, sort)
	if sort == "new" then
		return rows
	end
	return Sort:sort(rows, sort)
end

-- Build a paginated link Listing from get_listing `filters`, reading
-- sort/t/limit/after/before from the request.
local function link_listing(self, filters)
	local sort = self.params.sort
	if not SORTS[sort] then
		sort = "hot"
	end
	filters.since = timewindow(self.params.t)
	local user = current_user(self)
	if user then
		filters.exclude_hidden_for = user.id
	end

	local rows = sorted_listing(Posts:get_listing(filters), sort)
	local page, after, before = S.paginate(rows, self.params, "link")
	local children = {}
	for _, p in ipairs(page) do
		children[#children + 1] = S.link(p)
	end
	return { json = S.listing(children, { after = after, before = before }) }
end

-- Nest a flat (path-ordered) thread into Reddit's recursive reply Listings.
local function comment_tree(post_id)
	local by_id, roots = {}, {}
	for _, row in ipairs(Comments:thread(post_id)) do
		local thing = S.comment(row)
		by_id[row.id] = thing
		local parent = row.parent_comment_id and by_id[row.parent_comment_id]
		if parent then
			if parent.data.replies == "" then
				parent.data.replies = S.listing({})
			end
			local kids = parent.data.replies.data.children
			kids[#kids + 1] = thing
			parent.data.replies.data.dist = #kids
		else
			roots[#roots + 1] = thing
		end
	end
	return S.listing(roots)
end

-- ---- the routes --------------------------------------------------------------

local function api(app)
	-- Friendly index so a bare GET /api isn't a 404.
	app:get("/api", function()
		return {
			json = {
				name = "Page Six API",
				note = "Reddit-flavoured JSON. Things are wrapped { kind, data }.",
			},
		}
	end)

	-- ---- account ----

	-- The current account (Reddit returns the account `data` object directly).
	app:get("/api/v1/me", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		return { json = S.account(user).data }
	end)

	-- Karma split into link (post) vs comment karma, Reddit's KarmaList shape.
	app:get("/api/v1/me/karma", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local link = db.select(
			[[COALESCE((SELECT SUM(CASE WHEN v.upvote = 1 THEN 1 ELSE -1 END)
				FROM votes v JOIN posts p ON v.post_id = p.id
				WHERE v.comment_id IS NULL AND p.user_id = ?), 0) AS k]],
			user.id
		)[1].k
		local comment = db.select(
			[[COALESCE((SELECT SUM(CASE WHEN v.upvote = 1 THEN 1 ELSE -1 END)
				FROM votes v JOIN comments c ON v.comment_id = c.id
				WHERE c.user_id = ?), 0) AS k]],
			user.id
		)[1].k
		return {
			json = {
				kind = "KarmaList",
				data = {
					{
						sr = "",
						link_karma = tonumber(link) or 0,
						comment_karma = tonumber(comment) or 0,
					},
				},
			},
		}
	end)

	-- The current user's saved posts.
	app:get("/api/me/saved", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		return link_listing(self, { saved_for = user.id })
	end)

	-- ---- listings ----

	-- Frontpage listing: GET /api/listing(/:sort)
	app:get("/api/listing(/:sort)", function(self)
		return link_listing(self, {})
	end)

	-- Subreddit "about": GET /api/r/:subreddit/about  (registered before the
	-- sort catch-all so the literal `about` segment wins).
	app:get("/api/r/:subreddit/about", function(self)
		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return err(404, "Subreddit not found")
		end
		return { json = S.subreddit(sub) }
	end)

	-- Subreddit listing: GET /api/r/:subreddit(/:sort)
	app:get("/api/r/:subreddit(/:sort)", function(self)
		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return err(404, "Subreddit not found")
		end
		return link_listing(self, { sub_id = sub.id })
	end)

	-- A post and its comment tree: GET /api/comments/:post_id
	-- Returns Reddit's two-element array: [ link Listing, comment Listing ].
	app:get("/api/comments/:post_id[%d]", function(self)
		local post = Posts:find(tonumber(self.params.post_id))
		if not post or tonumber(post.deleted) == 1 then
			return err(404, "Post not found")
		end
		return { json = { S.listing({ S.link(post) }), comment_tree(post.id) } }
	end)

	-- ---- lookup ----

	-- GET /api/info?id=t3_x,t1_y,t5_z -- resolve fullnames to Things.
	app:get("/api/info", function(self)
		local children = {}
		for name in tostring(self.params.id or ""):gmatch("[^,]+") do
			local tbl, id = S.parse_fullname(name:match("^%s*(.-)%s*$"))
			if tbl == "posts" then
				local p = Posts:find(id)
				if p and tonumber(p.deleted) ~= 1 then
					children[#children + 1] = S.link(p)
				end
			elseif tbl == "comments" then
				local c = Comments:find(id)
				if c then
					children[#children + 1] = S.comment(c)
				end
			elseif tbl == "forum" then
				local f = Forum:find(id)
				if f then
					children[#children + 1] = S.subreddit(f)
				end
			elseif tbl == "users" then
				local u = Users:find(id)
				if u then
					children[#children + 1] = S.account(u)
				end
			end
		end
		return { json = S.listing(children) }
	end)

	-- ---- search ----

	-- Full-text post search: GET /api/search?q=
	app:get("/api/search", function(self)
		local rows = Posts:search(self.params.q)
		local page, after, before = S.paginate(rows, self.params, "link")
		local children = {}
		for _, p in ipairs(page) do
			children[#children + 1] = S.link(p)
		end
		return { json = S.listing(children, { after = after, before = before }) }
	end)

	-- ---- subreddits ----

	-- Subreddit name search: GET /api/subreddits/search?q=
	-- Forum:search projects list-card columns (no id); re-resolve each by name so
	-- the API emits full Things (id/name/uuid) rather than degraded ones.
	app:get("/api/subreddits/search", function(self)
		local children = {}
		for _, f in ipairs(Forum:search(self.params.q, tonumber(self.params.limit))) do
			local full = Forum:find({ name = f.name })
			if full then
				children[#children + 1] = S.subreddit(full)
			end
		end
		return { json = S.listing(children) }
	end)

	-- Subreddit directory: GET /api/subreddits(/:where) where=popular|new|default
	app:get("/api/subreddits(/:where)", function(self)
		local order = self.params.where == "new" and "s.created_at DESC"
			or "subscribers DESC, s.name"
		local rows = db.select([[
			s.id, s.name, s.description, s.nsfw, s.created_at,
				(SELECT COUNT(*) FROM subscriptions x WHERE x.subreddit_id = s.id) AS subscribers
			FROM forum s WHERE s.deleted_at IS NULL
			ORDER BY ]] .. order)
		local page, after, before = S.paginate(rows, self.params, "subreddit")
		local children = {}
		for _, f in ipairs(page) do
			children[#children + 1] = S.subreddit(f)
		end
		return { json = S.listing(children, { after = after, before = before }) }
	end)

	-- ---- users ----

	-- GET /api/user/:username/about -- an account Thing.
	app:get("/api/user/:username/about", function(self)
		local user = Users:find({ user_name = self.params.username })
		if not user then
			return err(404, "User not found")
		end
		return { json = S.account(user) }
	end)

	-- GET /api/username_available?user=
	app:get("/api/username_available", function(self)
		local name = self.params.user
		if not name or name == "" then
			return err(400, "Missing user")
		end
		local reserved = db.select(
			"1 FROM reserved_usernames WHERE user_name = ? LIMIT 1",
			tostring(name):lower()
		)[1]
		local taken = Users:find({ user_name = name }) ~= nil
		return { json = { available = (not reserved) and not taken } }
	end)

	-- ---- writes (auth + CSRF) ----

	-- POST /api/vote  { id = t3_/t1_ fullname, dir = 1 | 0 | -1 }
	app:post("/api/vote", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local dir = tonumber(self.params.dir)
		if dir ~= 1 and dir ~= 0 and dir ~= -1 then
			return err(400, "dir must be 1, 0, or -1")
		end
		local tbl, id = S.parse_fullname(self.params.id)
		if tbl == "posts" then
			local post = Posts:find(id)
			if not post then
				return err(404, "Post not found")
			end
			Votes:set(user.id, post.id, nil, dir)
			Users:recompute_reputation(post.user_id)
			return { json = { ok = true, id = self.params.id, score = Votes:post_score(post.id) } }
		elseif tbl == "comments" then
			local comment = Comments:find(id)
			if not comment then
				return err(404, "Comment not found")
			end
			Votes:set(user.id, comment.post_id, comment.id, dir)
			Users:recompute_reputation(comment.user_id)
			return {
				json = { ok = true, id = self.params.id, score = Votes:comment_score(comment.id) },
			}
		end
		return err(400, "Unknown thing id")
	end)

	-- Save/hide share a shape: a t3_ id and an idempotent set-to-state toggle.
	local function set_post_flag(self, model, want)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local tbl, id = S.parse_fullname(self.params.id)
		if tbl ~= "posts" then
			return err(400, "Expected a link (t3_) id")
		end
		if not Posts:find(id) then
			return err(404, "Post not found")
		end
		local is_set = model == SavedPosts and SavedPosts:is_saved(user.id, id)
			or model == HiddenPosts and HiddenPosts:is_hidden(user.id, id)
		if is_set ~= want then
			model:toggle(user.id, id)
		end
		return { json = { ok = true } }
	end

	app:post("/api/save", function(self)
		return set_post_flag(self, SavedPosts, true)
	end)
	app:post("/api/unsave", function(self)
		return set_post_flag(self, SavedPosts, false)
	end)
	app:post("/api/hide", function(self)
		return set_post_flag(self, HiddenPosts, true)
	end)
	app:post("/api/unhide", function(self)
		return set_post_flag(self, HiddenPosts, false)
	end)

	-- POST /api/subscribe { sr = t5_ fullname OR sr_name = name, action = sub|unsub }
	app:post("/api/subscribe", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local sub
		if self.params.sr then
			local tbl, id = S.parse_fullname(self.params.sr)
			sub = tbl == "forum" and Forum:find(id) or nil
		elseif self.params.sr_name then
			sub = Forum:find({ name = self.params.sr_name })
		end
		if not sub then
			return err(404, "Subreddit not found")
		end
		local want = self.params.action ~= "unsub"
		if Subscriptions:is_subscribed(user.id, sub.id) ~= want then
			Subscriptions:toggle(user.id, sub.id)
		end
		return { json = { ok = true, subscribed = want } }
	end)

	-- POST /api/submit { sr = name, kind = link|self, title, url, text }
	app:post("/api/submit", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local sub = Forum:find({ name = self.params.sr or self.params.subreddit })
		if not sub then
			return err(404, "Subreddit not found")
		end

		local url = self.params.url
		local text = self.params.text or self.params.body
		local is_self = self.params.kind == "self" or ((url == nil or url == "") and text)
		if is_self then
			url = nil
		elseif url == nil or url == "" then
			return err(400, "Provide a url (link post) or text (self post)")
		end

		local Spam = require("src.utils.spam")
		if Spam.is_spam((self.params.title or "") .. " " .. (text or "")) then
			return err(422, "Your post looks like spam.")
		end
		if require("src.utils.ratelimit").exceeded("posts", user.id, POST_RATE, POST_WINDOW) then
			return err(429, "You're posting too fast. Try again later.")
		end

		local held = require("src.utils.queue").should_hold(user, sub)
		local post, create_err = Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = self.params.title,
			url = url,
			body = (text ~= "") and text or nil,
			is_self = is_self and 1 or 0,
			thumbnail = require("src.utils.media").thumbnail_for(url),
			approved = held and 0 or 1,
		})
		if not post then
			return err(422, create_err)
		end
		require("src.models.tags"):set_for_post(post.id, self.params.tags)

		post.author, post.subreddit = user.user_name, sub.name
		post.upvotes, post.downvotes, post.num_comments = 0, 0, 0
		return { status = 201, json = { ok = true, pending = held, thing = S.link(post) } }
	end)

	-- POST /api/comment { parent = t3_/t1_ fullname, text }
	app:post("/api/comment", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local tbl, id = S.parse_fullname(self.params.parent)
		local post, parent
		if tbl == "posts" then
			post = Posts:find(id)
		elseif tbl == "comments" then
			parent = Comments:find(id)
			post = parent and Posts:find(parent.post_id)
		end
		if not post then
			return err(404, "Parent not found")
		end
		if tonumber(post.comments_locked) == 1 then
			return err(403, "This thread is locked")
		end

		local Spam = require("src.utils.spam")
		if Spam.is_spam(self.params.text) then
			return err(422, "Your comment looks like spam.")
		end
		if
			require("src.utils.ratelimit").exceeded(
				"comments",
				user.id,
				COMMENT_RATE,
				COMMENT_WINDOW
			)
		then
			return err(429, "You're commenting too fast. Try again later.")
		end

		local sub = Forum:find(post.sub_id)
		local held = require("src.utils.queue").should_hold(user, sub)
		local comment, create_err = Comments:create({
			post_id = post.id,
			user_id = user.id,
			parent_comment_id = parent and parent.id or nil,
			body = self.params.text,
			is_submitter = post.user_id == user.id and 1 or 0,
			approved = held and 0 or 1,
		})
		if not comment then
			return err(422, create_err)
		end
		if not held then
			local recipient = parent and parent.user_id or post.user_id
			if tonumber(recipient) ~= tonumber(user.id) then
				require("models.notifications"):notify(
					recipient,
					comment.id,
					parent and "comment_reply" or "post_reply"
				)
			end
		end

		-- Shape a thread-style row so the serializer has author/subreddit/score.
		comment.author, comment.subreddit = user.user_name, sub.name
		comment.upvotes, comment.downvotes = 0, 0
		return { status = 201, json = { ok = true, pending = held, thing = S.comment(comment) } }
	end)

	-- POST /api/del { id = t3_/t1_ } -- soft-delete your own post or comment.
	app:post("/api/del", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local tbl, id = S.parse_fullname(self.params.id)
		if tbl == "posts" then
			local post = Posts:find(id)
			if post and post.user_id == user.id then
				post:update({ deleted = 1 })
			end
		elseif tbl == "comments" then
			local comment = Comments:find(id)
			if comment and comment.user_id == user.id then
				comment:update({ deleted = 1 })
			end
		else
			return err(400, "Unknown thing id")
		end
		return { json = { ok = true } }
	end)

	-- POST /api/editusertext { thing_id = t3_/t1_, text } -- edit your own text.
	app:post("/api/editusertext", function(self)
		local user = current_user(self)
		if not user then
			return err(401, "Unauthorized")
		end
		local tbl, id = S.parse_fullname(self.params.thing_id)
		if tbl == "posts" then
			local post = Posts:find(id)
			if not post or post.user_id ~= user.id then
				return err(403, "Not your post")
			end
			if tonumber(post.is_self) ~= 1 or tonumber(post.deleted) == 1 then
				return err(422, "Only your own non-deleted self-posts are editable")
			end
			post:update({ body = self.params.text, edited = 1 })
			return { json = { ok = true, thing = S.link(post) } }
		elseif tbl == "comments" then
			local comment = Comments:find(id)
			if not comment or comment.user_id ~= user.id then
				return err(403, "Not your comment")
			end
			if tonumber(comment.deleted) == 1 then
				return err(422, "Deleted comments can't be edited")
			end
			local ok, update_err = comment:update({ body = self.params.text, edited = 1 })
			if not ok then
				return err(422, update_err)
			end
			return { json = { ok = true } }
		end
		return err(400, "Unknown thing id")
	end)

	return app
end

return api

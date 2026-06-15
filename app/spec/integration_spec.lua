--- Integration spec: drives the real app through simulate_request (routing,
--- actions, auth/session, redirects, rendering) for each feature.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("pagesix integration", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local Subscriptions = require("models.subscriptions")
	local app = require("app")

	-- CSRF: the global before_filter validates a `csrf_token` param against a
	-- `<session_name>_token` cookie. The key inside the token only has to match
	-- the cookie, so we mint one matching (cookie, token) pair and reuse it for
	-- every POST helper call (see app.lua / lapis.csrf).
	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	local function GET(url)
		return simulate_request(app, url, { method = "GET" })
	end
	local function POST(url, params, user)
		params = params or {}
		if params.csrf_token == nil then
			params.csrf_token = CSRF_TOKEN
		end
		return simulate_request(app, url, {
			method = "POST",
			post = params,
			session = user and { current_user = user } or nil,
			cookies = { [CSRF_COOKIE] = CSRF_KEY },
		})
	end

	setup(function()
		require("spec.schema_helper")()
		local u =
			Users:create({ user_name = "demo", user_pass = "password", user_email = "d@e.com" })
		local s = Forum:create({ name = "programming", creator_id = u.id, description = "Coding" })
		local p = Posts:create({
			user_id = u.id,
			sub_id = s.id,
			title = "Hello World",
			url = "https://example.com/x",
		})
		Comments:create({ post_id = p.id, user_id = u.id, body = "first comment" })
	end)

	describe("browsing (GET)", function()
		it("renders the frontpage with posts", function()
			local status, body = GET("/")
			assert.same(200, status)
			assert.truthy(body:find("Hello World", 1, true))
		end)

		it("renders a subreddit and its sorts", function()
			assert.same(200, (GET("/r/programming")))
			assert.same(200, (GET("/r/programming/top")))
			assert.same(200, (GET("/r/programming/controversial")))
		end)

		it("renders the meta listings /r/all and /r/popular", function()
			assert.same(200, (GET("/r/all")))
			assert.same(200, (GET("/r/all/top")))
			assert.same(200, (GET("/r/popular")))
		end)

		it("lists subreddits", function()
			local status, body = GET("/subreddits")
			assert.same(200, status)
			assert.truthy(body:find("/r/programming", 1, true))
		end)

		it("renders a post page with its comment", function()
			local status, body = GET("/r/programming/comments/1/_")
			assert.same(200, status)
			assert.truthy(body:find("first comment", 1, true))
		end)

		it("renders a single-comment permalink with its replies and ?context", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "perma post",
				url = "https://perma.example",
			})
			local root = Comments:create({ post_id = p.id, user_id = 1, body = "PERMA_ROOT" })
			local child = Comments:create({
				post_id = p.id,
				user_id = 1,
				body = "PERMA_CHILD",
				parent_comment_id = root.id,
			})
			Comments:create({
				post_id = p.id,
				user_id = 1,
				body = "PERMA_REPLY",
				parent_comment_id = child.id,
			})
			local base = "/r/programming/comments/" .. p.id .. "/_/" .. child.id

			-- No context: the focused comment + its reply, but not the parent.
			local s1, b1 = GET(base)
			assert.same(200, s1)
			assert.truthy(b1:find("PERMA_CHILD", 1, true))
			assert.truthy(b1:find("PERMA_REPLY", 1, true)) -- subtree included
			assert.is_nil(b1:find("PERMA_ROOT", 1, true)) -- ancestor excluded

			-- context=1 pulls in the parent comment above.
			local s2, b2 = simulate_request(app, base, { method = "GET", get = { context = "1" } })
			assert.same(200, s2)
			assert.truthy(b2:find("PERMA_ROOT", 1, true))
			assert.truthy(b2:find("PERMA_CHILD", 1, true))
		end)

		it("renders a user profile", function()
			local status, body = GET("/user/demo")
			assert.same(200, status)
			assert.truthy(body:find("Hello World", 1, true))
		end)

		it("redirects unknown users and subreddits home", function()
			local status = GET("/user/nobody")
			assert.same(302, status)
			assert.same(302, (GET("/r/nosuchsub")))
		end)
	end)

	describe("auth", function()
		local Password = require("src.utils.password")

		-- GET an auth page to obtain a CSRF token + its cookie (in the headers).
		local function csrf_for(path)
			local _, body, headers = simulate_request(app, path, { method = "GET" })
			return (body:match('name="csrf_token"%s+value="([^"]*)"')), headers
		end

		it("hashes and verifies passwords (bcrypt)", function()
			local h = Password.hash("hunter2pass")
			assert.is_true(h ~= "hunter2pass")
			assert.is_true(Password.verify("hunter2pass", h))
			assert.is_false(Password.verify("wrong", h))
			assert.is_false(Password.verify("x", "legacy-plaintext")) -- non-bcrypt
		end)

		it("logs in with valid credentials and a CSRF token", function()
			Users:create({
				user_name = "authuser",
				user_pass = Password.hash("secret123"),
				user_email = "au@e.com",
			})
			local token, headers = csrf_for("/login")
			assert.is_true(token ~= nil and #token > 0)
			local status = simulate_request(app, "/login", {
				method = "POST",
				prev = headers,
				post = { username = "authuser", password = "secret123", csrf_token = token },
			})
			assert.same(302, status)
		end)

		it("rejects a wrong password (re-renders, no redirect)", function()
			Users:create({
				user_name = "authuser2",
				user_pass = Password.hash("secret123"),
				user_email = "au2@e.com",
			})
			local token, headers = csrf_for("/login")
			local status, body = simulate_request(app, "/login", {
				method = "POST",
				prev = headers,
				post = { username = "authuser2", password = "WRONG", csrf_token = token },
			})
			assert.same(200, status)
			assert.truthy(body:find("Invalid username or password", 1, true))
		end)

		it("rejects a login POST without a CSRF token (403, global filter)", function()
			Users:create({
				user_name = "authuser3",
				user_pass = Password.hash("secret123"),
				user_email = "au3@e.com",
			})
			local status, body = simulate_request(app, "/login", {
				method = "POST",
				post = { username = "authuser3", password = "secret123" },
			})
			assert.same(403, status) -- blocked before the action runs; not logged in
			assert.truthy(body:find("session expired", 1, true))
			assert.is_nil(Users:find({ user_name = "authuser3", user_pass = "secret123" }))
		end)

		it("blocks a state-changing form POST with no CSRF token", function()
			-- A signed-in vote is still rejected without a token: CSRF now covers
			-- every state-changing form, not just login/register.
			local status = simulate_request(app, "/subscribe/programming", {
				method = "POST",
				session = { current_user = "demo" },
			})
			assert.same(403, status)
		end)

		it("registers a new user with a hashed password", function()
			local token, headers = csrf_for("/register")
			local status = simulate_request(app, "/register", {
				method = "POST",
				prev = headers,
				post = {
					name = "newbie",
					passwd = "secret123",
					passwd2 = "secret123",
					email = "n@e.com",
					csrf_token = token,
				},
			})
			assert.same(302, status)
			local u = Users:find({ user_name = "newbie" })
			assert.is_not_nil(u)
			assert.is_true(Password.verify("secret123", u.user_pass)) -- stored hashed
		end)

		it("redirects gated actions to login when signed out", function()
			local status, _, headers = POST("/vote/post/1/up", {})
			assert.same(302, status)
			assert.truthy((headers.location or ""):find("/login", 1, true))
		end)

		it("re-hashes legacy plaintext passwords (migration [50])", function()
			-- An old seed stored the password verbatim; bcrypt can't verify it.
			local u = Users:create({
				user_name = "legacyplain",
				user_pass = "hunter2",
				user_email = "lp@e.com",
			})
			assert.is_false(Password.verify("hunter2", u.user_pass))

			require("migrations")[50]()

			local migrated = Users:find(u.id)
			assert.is_true(Password.verify("hunter2", migrated.user_pass))
		end)
	end)

	describe("password reset", function()
		local Password = require("src.utils.password")
		local PasswordResets = require("models.password_resets")

		it("issues a token, sets a new password, and signs the user in", function()
			local u = Users:create({
				user_name = "resetme",
				user_pass = Password.hash("oldpass1"),
				user_email = "reset@e.com",
			})

			-- Request a reset; dev surfaces the link (with token) in the page.
			local status, body = POST("/password", { username = "resetme" })
			assert.same(200, status)
			local token = body:match("token=([a-f0-9]+)")
			assert.is_true(token ~= nil and #token > 0)

			assert.same(200, (GET("/password/reset?token=" .. token)))

			local s2 = POST("/password/reset", {
				token = token,
				passwd = "brandnew1",
				passwd2 = "brandnew1",
			})
			assert.same(302, s2) -- success: redirected and signed in

			local updated = Users:find(u.id)
			assert.is_true(Password.verify("brandnew1", updated.user_pass))
			assert.is_false(Password.verify("oldpass1", updated.user_pass))
			assert.is_nil(PasswordResets:valid(token)) -- token consumed
		end)

		it("rejects mismatched passwords and keeps the token", function()
			local u = Users:create({
				user_name = "resetmismatch",
				user_pass = Password.hash("oldpass1"),
				user_email = "rm@e.com",
			})
			local token = PasswordResets:issue(u.id)

			local status, body = POST("/password/reset", {
				token = token,
				passwd = "brandnew1",
				passwd2 = "different1",
			})
			assert.same(200, status)
			assert.truthy(body:find("do not match", 1, true))
			assert.is_not_nil(PasswordResets:valid(token)) -- not consumed
			assert.is_true(Password.verify("oldpass1", Users:find(u.id).user_pass))
		end)

		it("rejects an invalid token", function()
			local status, body = GET("/password/reset?token=deadbeef")
			assert.same(200, status)
			assert.truthy(body:find("invalid or has expired", 1, true))
		end)

		it("does not reveal whether an account exists", function()
			local status, body = POST("/password", { username = "nobody-here-at-all" })
			assert.same(200, status)
			assert.truthy(body:find("If an account matches", 1, true))
		end)
	end)

	describe("voting", function()
		it("records a post vote for a signed-in user", function()
			local status = POST("/vote/post/1/up", {}, "demo")
			assert.same(302, status)
			assert.truthy(#Votes:select("where post_id = 1 and comment_id is null") >= 1)
		end)

		it("records a comment vote", function()
			local status = POST("/vote/comment/1/up", {}, "demo")
			assert.same(302, status)
			assert.truthy(#Votes:select("where comment_id = 1") >= 1)
		end)
	end)

	describe("commenting", function()
		it("creates a top-level comment", function()
			local before = #Comments:select("where post_id = 1")
			local status = POST("/post/1/comment", { body = "a new comment" }, "demo")
			assert.same(302, status)
			assert.same(before + 1, #Comments:select("where post_id = 1"))
		end)

		it("rejects an empty comment (model constraint)", function()
			local before = #Comments:select("where post_id = 1")
			POST("/post/1/comment", { body = "" }, "demo")
			assert.same(before, #Comments:select("where post_id = 1"))
		end)

		it("threads a reply under its parent", function()
			local status =
				POST("/post/1/comment", { body = "a reply", parent_comment_id = "1" }, "demo")
			assert.same(302, status)
			local replies = Comments:select("where parent_comment_id = 1")
			assert.truthy(#replies >= 1)
		end)
	end)

	describe("editing & deleting comments", function()
		it("lets the author edit their comment", function()
			local c = Comments:create({ post_id = 1, user_id = 1, body = "original" })
			local status = POST("/comment/" .. c.id .. "/edit", { body = "edited body" }, "demo")
			assert.same(302, status)
			local updated = Comments:find(c.id)
			assert.same("edited body", updated.body)
			assert.same(1, tonumber(updated.edited))
		end)

		it("won't let a non-author edit", function()
			Users:create({ user_name = "intruder", user_pass = "password", user_email = "i@e.com" })
			local c = Comments:create({ post_id = 1, user_id = 1, body = "mine" })
			POST("/comment/" .. c.id .. "/edit", { body = "hacked" }, "intruder")
			assert.same("mine", Comments:find(c.id).body)
		end)

		it("soft-deletes the author's comment", function()
			local c = Comments:create({ post_id = 1, user_id = 1, body = "to delete" })
			local status = POST("/comment/" .. c.id .. "/delete", {}, "demo")
			assert.same(302, status)
			assert.same(1, tonumber(Comments:find(c.id).deleted))
		end)
	end)

	describe("editing & deleting posts", function()
		it("lets the author edit a self post", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "editable",
				body = "orig",
				is_self = 1,
			})
			local status = POST("/post/" .. p.id .. "/edit", { body = "new body" }, "demo")
			assert.same(302, status)
			local up = Posts:find(p.id)
			assert.same("new body", up.body)
			assert.same(1, tonumber(up.edited))
		end)

		it("soft-deletes the author's post and drops it from listings", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "deleteme",
				url = "https://d.example",
			})
			POST("/post/" .. p.id .. "/delete", {}, "demo")
			assert.same(1, tonumber(Posts:find(p.id).deleted))
			local found = false
			for _, row in ipairs(Posts:get_listing(1)) do
				if row.id == p.id then
					found = true
				end
			end
			assert.is_false(found)
		end)

		it("won't let a non-author delete", function()
			Users:create({
				user_name = "post_intruder",
				user_pass = "password",
				user_email = "pi@e.com",
			})
			local p =
				Posts:create({ user_id = 1, sub_id = 1, title = "safe", url = "https://s.example" })
			POST("/post/" .. p.id .. "/delete", {}, "post_intruder")
			assert.same(0, tonumber(Posts:find(p.id).deleted))
		end)
	end)

	describe("submitting posts", function()
		it("creates a self/text post and renders its Markdown body", function()
			local status, _, headers = POST(
				"/submit",
				{ title = "My text post", body = "hello **world**", subreddit = "programming" },
				"demo"
			)
			assert.same(302, status)

			local p = Posts:find({ title = "My text post" })
			assert.is_not_nil(p)
			assert.same(1, tonumber(p.is_self))
			assert.truthy(headers.location:find("/comments/" .. p.id, 1, true))

			local s2, body = GET("/r/programming/comments/" .. p.id .. "/my_text_post")
			assert.same(200, s2)
			assert.truthy(body:find("<strong>world</strong>", 1, true))
		end)

		it("creates a link post", function()
			local status = POST(
				"/submit",
				{ title = "A link post", url = "https://link.example", subreddit = "programming" },
				"demo"
			)
			assert.same(302, status)
			local p = Posts:find({ title = "A link post" })
			assert.is_not_nil(p)
			assert.same(0, tonumber(p.is_self))
		end)

		it("rejects a post with neither url nor body", function()
			POST("/submit", { title = "empty post", subreddit = "programming" }, "demo")
			assert.is_nil(Posts:find({ title = "empty post" }))
		end)

		it("previews a self-post's Markdown without creating it", function()
			local status, body = POST("/submit", {
				title = "preview me",
				body = "hello **bold**",
				subreddit = "programming",
				preview = "1",
			}, "demo")
			assert.same(200, status)
			assert.truthy(body:find("<strong>bold</strong>", 1, true))
			assert.is_nil(Posts:find({ title = "preview me" }))
		end)
	end)

	describe("spam filtering (lapis-bayes)", function()
		local Spam = require("src.utils.spam")
		-- The classifier is trained by migration [12] (run via schema_helper).
		local SPAM = "free money click here to win a prize claim your free gift card now"
		local HAM = "i was reading about recursive ctes in sqlite for my lua project today"

		it("classifies obvious spam vs ham", function()
			assert.is_true(Spam.is_spam(SPAM))
			assert.is_false(Spam.is_spam(HAM))
		end)

		it("blocks a spammy post submission", function()
			local status = POST(
				"/submit",
				{ title = "WINNER", body = SPAM, subreddit = "programming" },
				"demo"
			)
			assert.same(200, status) -- re-rendered with an error, not a 302 redirect
			assert.is_nil(Posts:find({ title = "WINNER" }))
		end)

		it("allows a non-spam post submission", function()
			local status = POST(
				"/submit",
				{ title = "Lua CTE question", body = HAM, subreddit = "programming" },
				"demo"
			)
			assert.same(302, status)
			assert.is_not_nil(Posts:find({ title = "Lua CTE question" }))
		end)

		it("drops a spammy comment", function()
			POST("/post/1/comment", { body = SPAM }, "demo")
			assert.is_nil(Comments:find({ body = SPAM }))
		end)
	end)

	describe("image posts + thumbnails", function()
		it("sets a thumbnail for an image link and renders a preview", function()
			local status = POST("/submit", {
				title = "a cat pic",
				url = "https://i.example/cat.jpg",
				subreddit = "programming",
			}, "demo")
			assert.same(302, status)
			local p = Posts:find({ title = "a cat pic" })
			assert.same("https://i.example/cat.jpg", p.thumbnail)

			local s2, body = GET("/r/programming/comments/" .. p.id .. "/a_cat_pic")
			assert.same(200, s2)
			assert.truthy(body:find('src="https://i.example/cat.jpg"', 1, true))
		end)

		it("leaves no thumbnail for a non-image link", function()
			POST("/submit", {
				title = "an article",
				url = "https://news.example/story",
				subreddit = "programming",
			}, "demo")
			local p = Posts:find({ title = "an article" })
			assert.is_nil(p.thumbnail)
		end)
	end)

	describe("crossposts", function()
		it("reposts into another subreddit with attribution back to the source", function()
			local orig = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "xpost me",
				url = "https://x.example/img.png",
				thumbnail = "https://x.example/img.png",
			})
			local target = Forum:create({ name = "xpost_target", creator_id = 1 })

			local status =
				POST("/post/" .. orig.id .. "/crosspost", { subreddit = "xpost_target" }, "demo")
			assert.same(302, status)

			local xp = Posts:find({ sub_id = target.id, crosspost_parent_id = orig.id })
			assert.is_not_nil(xp)
			assert.same("xpost me", xp.title)

			local s2, body = GET("/r/xpost_target/comments/" .. xp.id .. "/xpost_me")
			assert.same(200, s2)
			assert.truthy(body:find("crossposted from", 1, true))
			assert.truthy(body:find("/r/programming", 1, true)) -- source sub (sub_id 1)
		end)

		it("keeps crosspost chains one level deep", function()
			local orig = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "chain root",
				url = "https://x.example/y",
			})
			local t1 = Forum:create({ name = "chain_a", creator_id = 1 })
			local t2 = Forum:create({ name = "chain_b", creator_id = 1 })

			POST("/post/" .. orig.id .. "/crosspost", { subreddit = "chain_a" }, "demo")
			local xp1 = Posts:find({ sub_id = t1.id, crosspost_parent_id = orig.id })
			assert.is_not_nil(xp1)

			-- Crossposting the crosspost should still point at the original root.
			POST("/post/" .. xp1.id .. "/crosspost", { subreddit = "chain_b" }, "demo")
			local xp2 = Posts:find({ sub_id = t2.id })
			assert.same(orig.id, tonumber(xp2.crosspost_parent_id))
		end)
	end)

	describe("subreddit creation", function()
		it("creates a subreddit", function()
			local status =
				POST("/subreddit/create", { name = "newcommunity", description = "x" }, "demo")
			assert.same(302, status)
			assert.is_not_nil(Forum:find({ name = "newcommunity" }))
		end)

		it("rejects a reserved name", function()
			POST("/subreddit/create", { name = "all" }, "demo")
			assert.is_nil(Forum:find({ name = "all" }))
		end)
	end)

	describe("moderation: sticky / lock / modlog", function()
		-- "demo" created /r/programming in setup, so demo can moderate it.
		local function make_post(title)
			return Posts:create({
				user_id = 1,
				sub_id = 1,
				title = title,
				url = "https://mod.example/" .. title,
			})
		end

		it("lets a mod sticky and unsticky a post (pinned in the listing)", function()
			local p = make_post("sticky-target")
			local status = POST("/post/" .. p.id .. "/sticky", {}, "demo")
			assert.same(302, status)
			assert.same(1, tonumber(Posts:find(p.id).stickied))

			local s2, body = GET("/r/programming")
			assert.same(200, s2)
			assert.truthy(body:find("stickied", 1, true)) -- badge in the listing

			POST("/post/" .. p.id .. "/sticky", {}, "demo") -- toggle back off
			assert.same(0, tonumber(Posts:find(p.id).stickied))
		end)

		it("lets a mod lock a thread, blocking new comments", function()
			local p = make_post("lock-target")
			local before = #Comments:select("where post_id = " .. p.id)

			POST("/post/" .. p.id .. "/lock", {}, "demo")
			assert.same(1, tonumber(Posts:find(p.id).comments_locked))

			-- A comment on the locked thread is rejected (redirects, no insert).
			local status =
				POST("/post/" .. p.id .. "/comment", { body = "should be blocked" }, "demo")
			assert.same(302, status)
			assert.same(before, #Comments:select("where post_id = " .. p.id))

			-- The post page shows the locked notice instead of a comment form.
			local _, body = GET("/r/programming/comments/" .. p.id .. "/lock_target")
			assert.truthy(body:find("This thread is locked", 1, true))

			-- Unlocking restores commenting.
			POST("/post/" .. p.id .. "/lock", {}, "demo")
			assert.same(0, tonumber(Posts:find(p.id).comments_locked))
			POST("/post/" .. p.id .. "/comment", { body = "now allowed" }, "demo")
			assert.same(before + 1, #Comments:select("where post_id = " .. p.id))
		end)

		it("ignores moderation actions from a non-moderator", function()
			Users:create({
				user_name = "not_a_mod",
				user_pass = "password",
				user_email = "nm@e.com",
			})
			local p = make_post("nonmod-target")
			POST("/post/" .. p.id .. "/sticky", {}, "not_a_mod")
			assert.same(0, tonumber(Posts:find(p.id).stickied))
			POST("/post/" .. p.id .. "/lock", {}, "not_a_mod")
			assert.same(0, tonumber(Posts:find(p.id).comments_locked))
		end)

		it("records actions on the public modlog page", function()
			local p = make_post("modlog-target")
			POST("/post/" .. p.id .. "/sticky", {}, "demo")
			POST("/post/" .. p.id .. "/remove", {}, "demo")

			local status, body = GET("/r/programming/modlog")
			assert.same(200, status)
			assert.truthy(body:find("moderation log", 1, true))
			assert.truthy(body:find("stickied", 1, true))
			assert.truthy(body:find("removed", 1, true))
			assert.truthy(body:find("demo", 1, true)) -- the acting moderator
		end)
	end)

	describe("RSS import (live)", function()
		local feed_import = require("src.utils.feed_import")
		local Feeds = require("models.feeds")

		local RSS = [[<?xml version="1.0"?><rss version="2.0"><channel>
			<title>Imp</title>
			<item><title>Imported A</title><link>https://imp.example/a</link><guid>impA</guid></item>
			<item><title>Imported B</title><link>https://imp.example/b</link><guid>impB</guid></item>
		</channel></rss>]]

		it("imports new entries and dedups on re-run", function()
			local bot = Feeds:bot()
			local n1 = feed_import.import_entries(1, bot.id, {
				{ title = "X", link = "https://d.example/x", guid = "gx" },
				{ title = "Y", link = "https://d.example/y", guid = "gy" },
			})
			assert.same(2, n1)
			assert.is_not_nil(Posts:find({ external_guid = "gx" }))

			-- Re-importing the same guids creates nothing.
			local n2 = feed_import.import_entries(1, bot.id, {
				{ title = "X", link = "https://d.example/x", guid = "gx" },
			})
			assert.same(0, n2)
		end)

		it("refreshes a subreddit's feeds via a stubbed fetch", function()
			Feeds:add(1, "https://imp.example/feed.xml")
			local orig = feed_import.fetch
			feed_import.fetch = function()
				return RSS, 200
			end

			assert.same(2, feed_import.refresh_subreddit(1))
			assert.is_not_nil(Posts:find({ external_guid = "impA" }))
			-- A second refresh of the same feed imports nothing new.
			assert.same(0, feed_import.refresh_subreddit(1))

			feed_import.fetch = orig
		end)

		it("records a fetch failure without importing", function()
			local f = Feeds:add(1, "https://dead.example/feed.xml")
			local imported = feed_import.refresh_feed(f, function()
				return nil, 500
			end)
			assert.same(0, imported)
			assert.same(1, tonumber(Feeds:find(f.id).failure_count))
		end)

		it("lets a moderator trigger a refresh; ignores non-mods", function()
			Feeds:add(1, "https://imp2.example/feed.xml")
			local RSS2 = [[<?xml version="1.0"?><rss version="2.0"><channel>
				<item><title>ModFetched</title><link>https://imp2.example/p</link><guid>mod1</guid></item>
			</channel></rss>]]
			local orig = feed_import.fetch
			feed_import.fetch = function()
				return RSS2, 200
			end

			-- A non-moderator can't trigger an import.
			Users:create({
				user_name = "feed_nonmod",
				user_pass = "password",
				user_email = "fn@e.com",
			})
			POST("/r/programming/feeds/refresh", {}, "feed_nonmod")
			assert.is_nil(Posts:find({ external_guid = "mod1" }))

			-- "demo" created /r/programming, so it can.
			local status = POST("/r/programming/feeds/refresh", {}, "demo")
			assert.same(302, status)
			assert.is_not_nil(Posts:find({ external_guid = "mod1" }))

			feed_import.fetch = orig
		end)

		it("Feeds:due honors last_fetched_at and exponential backoff", function()
			local f = Feeds:add(1, "https://due.example/feed.xml")
			local function due_has(base, id)
				for _, d in ipairs(Feeds:due(base)) do
					if tonumber(d.id) == tonumber(id) then
						return true
					end
				end
				return false
			end

			-- never fetched -> always due
			assert.is_true(due_has(900, f.id))

			-- after a success it's not due within the base interval...
			Feeds:record_result(f, true, 200)
			assert.is_false(due_has(900, f.id))
			-- ...but due again once the interval is treated as elapsed (base 0).
			assert.is_true(due_has(0, f.id))

			-- two failures -> backs off (waits base * min(2^2,64) = 4x), so a
			-- just-fetched failing feed is skipped at the normal interval.
			Feeds:record_result(Feeds:find(f.id), false, 500)
			Feeds:record_result(Feeds:find(f.id), false, 500)
			assert.same(2, tonumber(Feeds:find(f.id).failure_count))
			assert.is_false(due_has(900, f.id))
		end)

		it("sends conditional-GET validators and treats 304 as an unchanged success", function()
			local f = Feeds:add(1, "https://cond.example/feed.xml")

			-- First fetch: no validators cached yet; response carries them.
			feed_import.refresh_feed(f, function(_, headers)
				assert.is_nil(headers["If-None-Match"])
				return [[<rss version="2.0"><channel><item><title>C</title>
					<link>https://cond.example/p</link><guid>condg</guid></item></channel></rss>]],
					200,
					{ etag = '"abc"', ["last-modified"] = "Wed, 21 Oct 2015 07:28:00 GMT" }
			end)
			assert.is_not_nil(Posts:find({ external_guid = "condg" }))
			local saved = Feeds:find(f.id)
			assert.same('"abc"', saved.etag)
			assert.same("Wed, 21 Oct 2015 07:28:00 GMT", saved.last_modified)

			-- Next fetch: the cached validators are sent; a 304 imports nothing
			-- but still counts as a success (failure_count stays 0).
			local imported = feed_import.refresh_feed(saved, function(_, headers)
				assert.same('"abc"', headers["If-None-Match"])
				assert.same("Wed, 21 Oct 2015 07:28:00 GMT", headers["If-Modified-Since"])
				return nil, 304
			end)
			assert.same(0, imported)
			assert.same(0, tonumber(Feeds:find(f.id).failure_count))
		end)

		it("refresh_all imports from every due feed (scheduler entry point)", function()
			Feeds:add(1, "https://all.example/feed.xml") -- fresh -> due
			local orig = feed_import.fetch
			feed_import.fetch = function()
				return [[<rss version="2.0"><channel><item><title>All</title>
					<link>https://all.example/p</link><guid>allg</guid></item></channel></rss>]],
					200
			end

			local total, checked = feed_import.refresh_all(900)
			assert.is_true(checked >= 1)
			assert.is_true(total >= 1)
			assert.is_not_nil(Posts:find({ external_guid = "allg" }))

			feed_import.fetch = orig
		end)

		it("shows the feed-management page to a mod and redirects others", function()
			local mod_status, mod_body = simulate_request(app, "/r/programming/feeds", {
				method = "GET",
				session = { current_user = "demo" }, -- demo created /r/programming
			})
			assert.same(200, mod_status)
			assert.truthy(mod_body:find("add feed", 1, true))

			Users:create({
				user_name = "ui_viewer",
				user_pass = "password",
				user_email = "uv@e.com",
			})
			local nm_status = simulate_request(app, "/r/programming/feeds", {
				method = "GET",
				session = { current_user = "ui_viewer" },
			})
			assert.same(302, nm_status) -- non-mod redirected away
		end)

		it("lets a mod add / toggle / remove a feed; ignores non-mods and bad URLs", function()
			Users:create({
				user_name = "ui_nonmod",
				user_pass = "password",
				user_email = "un@e.com",
			})

			-- a non-moderator can't add a feed
			POST("/r/programming/feeds/add", { url = "https://nm.example/feed.xml" }, "ui_nonmod")
			assert.is_nil(Feeds:find({ sub_id = 1, url = "https://nm.example/feed.xml" }))

			-- only http(s) URLs are accepted
			POST("/r/programming/feeds/add", { url = "not-a-url" }, "demo")
			assert.is_nil(Feeds:find({ sub_id = 1, url = "not-a-url" }))

			-- mod add succeeds (enabled by default)
			local s =
				POST("/r/programming/feeds/add", { url = "https://ui.example/feed.xml" }, "demo")
			assert.same(302, s)
			local f = Feeds:find({ sub_id = 1, url = "https://ui.example/feed.xml" })
			assert.is_not_nil(f)
			assert.same(1, tonumber(f.enabled))

			-- toggle disables it (the scheduler then skips it)
			POST("/r/programming/feeds/" .. f.id .. "/toggle", {}, "demo")
			assert.same(0, tonumber(Feeds:find(f.id).enabled))

			-- remove deletes the row
			POST("/r/programming/feeds/" .. f.id .. "/remove", {}, "demo")
			assert.is_nil(Feeds:find(f.id))
		end)
	end)

	describe("RSS output feeds", function()
		it("serves the frontpage feed as RSS XML", function()
			local status, body, headers = simulate_request(app, "/.rss", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("<rss", 1, true))
			assert.truthy(body:find("<item>", 1, true))
			local ct = headers["content-type"] or headers.content_type or ""
			assert.truthy(ct:find("rss", 1, true))
		end)

		it("serves a subreddit feed and XML-escapes content", function()
			local u = Users:create({
				user_name = "rss_user",
				user_pass = "password",
				user_email = "rss@e.com",
			})
			local f = Forum:create({ name = "rsssub", creator_id = u.id })
			Posts:create({
				user_id = u.id,
				sub_id = f.id,
				title = "A & B <tag>",
				url = "https://ab.example",
			})

			local status, body = simulate_request(app, "/r/rsssub/.rss", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("A &amp; B &lt;tag&gt;", 1, true))
		end)

		it("404s an unknown subreddit feed", function()
			local status = simulate_request(app, "/r/nosuchsub/.rss", { method = "GET" })
			assert.same(404, status)
		end)
	end)

	describe("discoverability (sitemap / robots / well-known)", function()
		it("serves an XML sitemap of subreddits and posts", function()
			local status, body = simulate_request(app, "/sitemap.xml", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("<urlset", 1, true))
			assert.truthy(body:find("/r/programming", 1, true)) -- seeded subreddit
			assert.truthy(body:find("/comments/", 1, true)) -- a post permalink
		end)

		it("serves robots.txt pointing at the sitemap", function()
			local status, body = simulate_request(app, "/robots.txt", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("User%-agent: %*"))
			assert.truthy(body:find("Disallow: /login", 1, true))
			assert.truthy(body:find("Sitemap:", 1, true))
			assert.truthy(body:find("/sitemap.xml", 1, true))
		end)

		it("serves security.txt at the well-known location and root", function()
			for _, path in ipairs({ "/.well-known/security.txt", "/security.txt" }) do
				local status, body = simulate_request(app, path, { method = "GET" })
				assert.same(200, status)
				assert.truthy(body:find("Contact:", 1, true))
				assert.truthy(body:find("Expires:", 1, true))
			end
		end)
	end)

	describe("reply notifications", function()
		local Notifications = require("models.notifications")

		it("notifies the post author when someone comments", function()
			local op = Users:create({
				user_name = "notif_op",
				user_pass = "password",
				user_email = "no@e.com",
			})
			-- Established enough not to be held in the approval queue.
			Users:create({
				user_name = "notif_replier",
				user_pass = "password",
				user_email = "nr@e.com",
			}):update({ reputation = 50 })
			local f = Forum:create({ name = "notifsub", creator_id = op.id })
			local p = Posts:create({
				user_id = op.id,
				sub_id = f.id,
				title = "notif post",
				url = "https://n.example",
			})

			assert.same(0, Notifications:unread_count(op.id))
			POST("/post/" .. p.id .. "/comment", { body = "nice post" }, "notif_replier")
			assert.same(1, Notifications:unread_count(op.id))

			local list = Notifications:for_user(op.id)
			assert.same("post_reply", list[1].kind)
			assert.same("nice post", list[1].body)
		end)

		it("notifies the parent comment's author on a reply", function()
			local a = Users:create({
				user_name = "notif_a",
				user_pass = "password",
				user_email = "na@e.com",
			})
			Users:create({ user_name = "notif_b", user_pass = "password", user_email = "nb@e.com" })
				:update({ reputation = 50 }) -- not held in the approval queue
			local f = Forum:create({ name = "notifsub2", creator_id = a.id })
			local p = Posts:create({
				user_id = a.id,
				sub_id = f.id,
				title = "np2",
				url = "https://n2.example",
			})
			local c = Comments:create({ post_id = p.id, user_id = a.id, body = "parent" })

			POST(
				"/post/" .. p.id .. "/comment",
				{ body = "a reply", parent_comment_id = tostring(c.id) },
				"notif_b"
			)
			assert.same(1, Notifications:unread_count(a.id))
			assert.same("comment_reply", Notifications:for_user(a.id)[1].kind)
		end)

		it("does not notify on a self-reply", function()
			local u = Users:create({
				user_name = "notif_self",
				user_pass = "password",
				user_email = "ns@e.com",
			})
			local f = Forum:create({ name = "notifsub3", creator_id = u.id })
			local p = Posts:create({
				user_id = u.id,
				sub_id = f.id,
				title = "np3",
				url = "https://n3.example",
			})

			POST("/post/" .. p.id .. "/comment", { body = "my own comment" }, "notif_self")
			assert.same(0, Notifications:unread_count(u.id))
		end)

		it("marks the inbox read when viewed", function()
			local op = Users:create({
				user_name = "notif_read",
				user_pass = "password",
				user_email = "nrd@e.com",
			})
			Users:create({
				user_name = "notif_reader2",
				user_pass = "password",
				user_email = "nr2@e.com",
			}):update({ reputation = 50 }) -- not held in the approval queue
			local f = Forum:create({ name = "notifsub4", creator_id = op.id })
			local p = Posts:create({
				user_id = op.id,
				sub_id = f.id,
				title = "np4",
				url = "https://n4.example",
			})
			POST("/post/" .. p.id .. "/comment", { body = "hi there" }, "notif_reader2")
			assert.same(1, Notifications:unread_count(op.id))

			local s, body = simulate_request(
				app,
				"/inbox",
				{ method = "GET", session = { current_user = "notif_read" } }
			)
			assert.same(200, s)
			assert.truthy(body:find("hi there", 1, true))
			assert.same(0, Notifications:unread_count(op.id))
		end)
	end)

	describe("moderation", function()
		local Modlog = require("src.models.modlog")

		it("recognizes the creator and moderators (join table)", function()
			local creator = Users:create({
				user_name = "mod_creator",
				user_pass = "password",
				user_email = "mc@e.com",
			})
			local modu = Users:create({
				user_name = "mod_user",
				user_pass = "password",
				user_email = "mu@e.com",
			})
			local other = Users:create({
				user_name = "mod_other",
				user_pass = "password",
				user_email = "mo@e.com",
			})
			local f = Forum:create({ name = "modsub", creator_id = creator.id })
			Forum:add_moderator(f.id, modu.id)

			assert.is_true(Forum:can_moderate(creator.id, f))
			assert.is_true(Forum:can_moderate(modu.id, f))
			assert.is_false(Forum:can_moderate(other.id, f))
		end)

		it("enforces foreign keys (PRAGMA foreign_keys = ON)", function()
			-- Votes is required at module scope; reuse it.
			-- a vote on a non-existent post is rejected by the FK constraint
			local ok = pcall(function()
				Votes:create({ user_id = 1, post_id = 999999, upvote = 1 })
			end)
			assert.is_false(ok)
		end)

		it("lets a moderator remove a post (logged), hiding it from listings", function()
			local creator = Users:create({
				user_name = "mod_creator2",
				user_pass = "password",
				user_email = "mc2@e.com",
			})
			local f = Forum:create({ name = "modsub2", creator_id = creator.id })
			local p = Posts:create({
				user_id = creator.id,
				sub_id = f.id,
				title = "bad post",
				url = "https://b.example",
			})

			assert.same(302, (POST("/post/" .. p.id .. "/remove", {}, "mod_creator2")))
			assert.same(1, tonumber(Posts:find(p.id).locked))
			assert.same(0, #Posts:get_listing(f.id))
			assert.truthy(#Modlog:select("where post_id = ?", p.id) >= 1)
		end)

		it("won't let a non-moderator remove", function()
			Users:create({ user_name = "not_mod", user_pass = "password", user_email = "nm@e.com" })
			local creator = Users:create({
				user_name = "mod_creator3",
				user_pass = "password",
				user_email = "mc3@e.com",
			})
			local f = Forum:create({ name = "modsub3", creator_id = creator.id })
			local p = Posts:create({
				user_id = creator.id,
				sub_id = f.id,
				title = "ok post",
				url = "https://o.example",
			})

			POST("/post/" .. p.id .. "/remove", {}, "not_mod")
			assert.same(0, tonumber(Posts:find(p.id).locked))
		end)
	end)

	describe("saved & hidden posts", function()
		local SavedPosts = require("models.saved_posts")
		local HiddenPosts = require("models.hidden_posts")

		it("saves/unsaves a post and lists it on /saved", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "save me please",
				url = "https://sv.example",
			})
			assert.same(302, (POST("/post/" .. p.id .. "/save", {}, "demo")))
			assert.is_true(SavedPosts:is_saved(1, p.id))

			local s, body = simulate_request(
				app,
				"/saved",
				{ method = "GET", session = { current_user = "demo" } }
			)
			assert.same(200, s)
			assert.truthy(body:find("save me please", 1, true))

			POST("/post/" .. p.id .. "/save", {}, "demo") -- toggle off
			assert.is_false(SavedPosts:is_saved(1, p.id))
		end)

		it("hides a post so it drops from a user's listing", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "hide me",
				url = "https://hd.example",
			})
			POST("/post/" .. p.id .. "/hide", {}, "demo")
			assert.is_true(HiddenPosts:is_hidden(1, p.id))

			local hidden_filtered = {}
			for _, r in ipairs(Posts:get_listing({ exclude_hidden_for = 1 })) do
				hidden_filtered[r.id] = true
			end
			assert.is_nil(hidden_filtered[p.id])

			local unfiltered = {}
			for _, r in ipairs(Posts:get_listing({})) do
				unfiltered[r.id] = true
			end
			assert.is_true(unfiltered[p.id])
		end)
	end)

	describe("sorting & time windows", function()
		local Sort = require("src.utils.sort")

		it("sorts by rising (velocity), tolerating missing fields", function()
			local hour_ago = os.date("!%Y-%m-%d %H:%M:%S", os.time() - 3600)
			local rows = {
				{ id = 1, upvotes = 2, downvotes = 0, age = hour_ago },
				{ id = 2, upvotes = 10, downvotes = 0, age = hour_ago },
				{ id = 3 }, -- missing fields, must not crash
			}
			local sorted = Sort:sort(rows, "rising")
			assert.same(2, sorted[1].id)
		end)

		it("filters a listing to a time window", function()
			local old = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "ancient",
				url = "https://o.example",
			})
			old:update({ created_at = "2000-01-01 00:00:00" })
			local recent = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "fresh window",
				url = "https://f.example",
			})

			local since = require("src.utils.timewindow")("day")
			local ids = {}
			for _, r in ipairs(Posts:get_listing({ sub_id = 1, since = since })) do
				ids[r.id] = true
			end
			assert.is_nil(ids[old.id])
			assert.is_true(ids[recent.id])
		end)

		it("renders /r/:sub/top?t=week", function()
			local s = simulate_request(
				app,
				"/r/programming/top",
				{ method = "GET", get = { t = "week" } }
			)
			assert.same(200, s)
		end)
	end)

	describe("pagination", function()
		-- The pure slicing logic is unit-tested in spec/paginate_spec.lua; these
		-- drive it through real requests.
		it("paginates the frontpage over HTTP", function()
			for i = 1, 30 do
				Posts:create({
					user_id = 1,
					sub_id = 1,
					title = "page post " .. i,
					url = "https://p" .. i .. ".example",
				})
			end
			local function PAGE(n)
				return simulate_request(app, "/", { method = "GET", get = { page = tostring(n) } })
			end

			local s1, b1 = PAGE(1)
			assert.same(200, s1)
			assert.truthy(b1:find("page 1", 1, true)) -- page nav rendered

			local s2, b2 = PAGE(2)
			assert.same(200, s2)
			assert.truthy(b2:find("page 2", 1, true))
		end)

		it("paginates a post's comment thread by root over HTTP", function()
			local post = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "thread paging",
				url = "https://thread.example",
			})
			-- 27 root comments -> 25 on page 1, 2 on page 2 (COMMENTS_PER_PAGE=25).
			for i = 1, 27 do
				Comments:create({
					post_id = post.id,
					user_id = 1,
					body = string.format("rootcomment_%03d", i),
				})
			end
			local function PAGE(n)
				return simulate_request(
					app,
					"/r/programming/comments/" .. post.id .. "/_",
					{ method = "GET", get = { page = tostring(n) } }
				)
			end

			local s1, b1 = PAGE(1)
			assert.same(200, s1)
			assert.truthy(b1:find("rootcomment_001", 1, true)) -- first root present
			assert.is_nil(b1:find("rootcomment_027", 1, true)) -- last root not yet
			assert.truthy(b1:find('rel="next"', 1, true)) -- next link rendered

			local s2, b2 = PAGE(2)
			assert.same(200, s2)
			assert.truthy(b2:find("rootcomment_027", 1, true)) -- spills onto page 2
			assert.is_nil(b2:find("rootcomment_001", 1, true))
			assert.truthy(b2:find('rel="prev"', 1, true)) -- prev link rendered
		end)

		it("paginates a user's profile over HTTP", function()
			local u = Users:create({
				user_name = "prolific",
				user_pass = "password",
				user_email = "p@e.com",
			})
			for i = 1, 27 do
				Posts:create({
					user_id = u.id,
					sub_id = 1,
					title = "prof post " .. i,
					url = "https://pp" .. i .. ".example",
				})
			end
			local function PAGE(n)
				return simulate_request(
					app,
					"/user/prolific",
					{ method = "GET", get = { page = tostring(n) } }
				)
			end

			local s1, b1 = PAGE(1)
			assert.same(200, s1)
			assert.truthy(b1:find("page 1", 1, true))
			assert.truthy(b1:find('rel="next"', 1, true)) -- >25 posts -> a next page

			local s2, b2 = PAGE(2)
			assert.same(200, s2)
			assert.truthy(b2:find("page 2", 1, true))
			assert.truthy(b2:find('rel="prev"', 1, true))
		end)
	end)

	describe("karma", function()
		it("sums votes on a user's posts and comments", function()
			local author = Users:create({
				user_name = "karma_author",
				user_pass = "password",
				user_email = "k@e.com",
			})
			local v1 = Users:create({
				user_name = "karma_v1",
				user_pass = "password",
				user_email = "k1@e.com",
			})
			local v2 = Users:create({
				user_name = "karma_v2",
				user_pass = "password",
				user_email = "k2@e.com",
			})
			local p = Posts:create({
				user_id = author.id,
				sub_id = 1,
				title = "karma post",
				url = "https://k.example",
			})
			Votes:cast(v1.id, p.id, nil, 1) -- +1
			Votes:cast(v2.id, p.id, nil, 0) -- -1
			Votes:cast(author.id, p.id, nil, 1) -- +1  => post net +1
			local c = Comments:create({ post_id = p.id, user_id = author.id, body = "hi" })
			Votes:cast(v1.id, p.id, c.id, 1) -- comment +1

			assert.same(2, Users:karma(author.id))
		end)
	end)

	describe("search (FTS5)", function()
		local function SEARCH(q)
			return simulate_request(app, "/search", { method = "GET", get = { q = q } })
		end

		it("finds posts by title and body, ranked, excluding non-matches", function()
			Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "Unique Zebra Headline",
				url = "https://z.example",
			})
			Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "plain title",
				body = "contains quokka here",
				is_self = 1,
			})

			local s1, body = SEARCH("Zebra")
			assert.same(200, s1)
			assert.truthy(body:find("Unique Zebra Headline", 1, true))

			local _, body2 = SEARCH("quokka") -- body match
			assert.truthy(body2:find("plain title", 1, true))

			local _, body3 = SEARCH("nonexistentxyzzy")
			assert.is_nil(body3:find("Unique Zebra Headline", 1, true))
		end)

		it("excludes deleted posts from search", function()
			local p = Posts:create({
				user_id = 1,
				sub_id = 1,
				title = "Searchable Platypus",
				url = "https://p.example",
			})
			assert.same(1, #Posts:search("Platypus"))
			p:update({ deleted = 1 })
			assert.same(0, #Posts:search("Platypus"))
		end)
	end)

	describe("subscriptions", function()
		it("toggles a subscription on and off", function()
			assert.same(302, (POST("/subscribe/programming", {}, "demo")))
			assert.same(1, #Subscriptions:select("where user_id = 1 and subreddit_id = 1"))
			POST("/subscribe/programming", {}, "demo") -- toggle off
			assert.same(0, #Subscriptions:select("where user_id = 1 and subreddit_id = 1"))
		end)

		it("lists subscriptions on /subscribed and in the header nav", function()
			POST("/subscribe/programming", {}, "demo")

			local s1, sub_body = simulate_request(
				app,
				"/subscribed",
				{ method = "GET", session = { current_user = "demo" } }
			)
			assert.same(200, s1)
			assert.truthy(sub_body:find("/r/programming", 1, true))

			-- the layout header shows "my subs" on any page when signed in
			local _, home =
				simulate_request(app, "/", { method = "GET", session = { current_user = "demo" } })
			assert.truthy(home:find("/r/programming", 1, true))

			POST("/subscribe/programming", {}, "demo") -- cleanup
		end)
	end)

	describe("navigation & static pages", function()
		it("renders the about/faq/help/contact pages", function()
			for _, path in ipairs({ "/about", "/faq", "/help", "/contact" }) do
				local status, body = GET(path)
				assert.same(200, status)
				assert.truthy(#body > 0)
			end
		end)

		it("shows a CSRF-protected logout control in the header when signed in", function()
			local _, body =
				simulate_request(app, "/", { method = "GET", session = { current_user = "demo" } })
			assert.truthy(body:find('action="/logout"', 1, true))
			assert.truthy(body:find("log out", 1, true))
		end)

		it("logs out via a CSRF-protected POST", function()
			local status, _, headers = POST("/logout", {}, "demo")
			assert.same(302, status)
			assert.is_not_nil(headers.location)
		end)
	end)
end)

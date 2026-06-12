--- Integration spec: drives the real app through mock_request (routing,
--- actions, auth/session, redirects, rendering) for each feature.

local use_test_env = require("lapis.spec").use_test_env
local mock_request = require("lapis.spec.request").mock_request

describe("pagesix integration", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local Subscriptions = require("models.subscriptions")
	local app = require("app")

	local function GET(url)
		return mock_request(app, url, { method = "GET" })
	end
	local function POST(url, params, user)
		return mock_request(app, url, {
			method = "POST",
			post = params or {},
			session = user and { current_user = user } or nil,
		})
	end

	setup(function()
		require("spec.schema_helper")()
		local u = Users:create({ user_name = "demo", user_pass = "password", user_email = "d@e.com" })
		local s = Forum:create({ name = "programming", creator_id = u.id, description = "Coding" })
		local p = Posts:create({ user_id = u.id, sub_id = s.id, title = "Hello World", url = "https://example.com/x" })
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
			local _, body, headers = mock_request(app, path, { method = "GET" })
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
			Users:create({ user_name = "authuser", user_pass = Password.hash("secret123"), user_email = "au@e.com" })
			local token, headers = csrf_for("/login")
			assert.is_true(token ~= nil and #token > 0)
			local status = mock_request(app, "/login", {
				method = "POST", prev = headers,
				post = { username = "authuser", password = "secret123", csrf_token = token },
			})
			assert.same(302, status)
		end)

		it("rejects a wrong password (re-renders, no redirect)", function()
			Users:create({ user_name = "authuser2", user_pass = Password.hash("secret123"), user_email = "au2@e.com" })
			local token, headers = csrf_for("/login")
			local status, body = mock_request(app, "/login", {
				method = "POST", prev = headers,
				post = { username = "authuser2", password = "WRONG", csrf_token = token },
			})
			assert.same(200, status)
			assert.truthy(body:find("Invalid username or password", 1, true))
		end)

		it("rejects a login POST without a CSRF token", function()
			Users:create({ user_name = "authuser3", user_pass = Password.hash("secret123"), user_email = "au3@e.com" })
			local status, body = mock_request(app, "/login", {
				method = "POST",
				post = { username = "authuser3", password = "secret123" },
			})
			assert.same(200, status) -- not a 302: not logged in
			assert.truthy(body:find("Invalid session", 1, true))
		end)

		it("registers a new user with a hashed password", function()
			local token, headers = csrf_for("/register")
			local status = mock_request(app, "/register", {
				method = "POST", prev = headers,
				post = { name = "newbie", passwd = "secret123", passwd2 = "secret123", email = "n@e.com", csrf_token = token },
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
			local status = POST("/post/1/comment", { body = "a reply", parent_comment_id = "1" }, "demo")
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
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "editable", body = "orig", is_self = 1 })
			local status = POST("/post/" .. p.id .. "/edit", { body = "new body" }, "demo")
			assert.same(302, status)
			local up = Posts:find(p.id)
			assert.same("new body", up.body)
			assert.same(1, tonumber(up.edited))
		end)

		it("soft-deletes the author's post and drops it from listings", function()
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "deleteme", url = "https://d.example" })
			POST("/post/" .. p.id .. "/delete", {}, "demo")
			assert.same(1, tonumber(Posts:find(p.id).deleted))
			local found = false
			for _, row in ipairs(Posts:get_listing(1)) do
				if row.id == p.id then found = true end
			end
			assert.is_false(found)
		end)

		it("won't let a non-author delete", function()
			Users:create({ user_name = "post_intruder", user_pass = "password", user_email = "pi@e.com" })
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "safe", url = "https://s.example" })
			POST("/post/" .. p.id .. "/delete", {}, "post_intruder")
			assert.same(0, tonumber(Posts:find(p.id).deleted))
		end)
	end)

	describe("submitting posts", function()
		it("creates a self/text post and renders its Markdown body", function()
			local status, _, headers = POST("/submit",
				{ title = "My text post", body = "hello **world**", subreddit = "programming" }, "demo")
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
			local status = POST("/submit",
				{ title = "A link post", url = "https://link.example", subreddit = "programming" }, "demo")
			assert.same(302, status)
			local p = Posts:find({ title = "A link post" })
			assert.is_not_nil(p)
			assert.same(0, tonumber(p.is_self))
		end)

		it("rejects a post with neither url nor body", function()
			POST("/submit", { title = "empty post", subreddit = "programming" }, "demo")
			assert.is_nil(Posts:find({ title = "empty post" }))
		end)
	end)

	describe("subreddit creation", function()
		it("creates a subreddit", function()
			local status = POST("/subreddit/create", { name = "newcommunity", description = "x" }, "demo")
			assert.same(302, status)
			assert.is_not_nil(Forum:find({ name = "newcommunity" }))
		end)

		it("rejects a reserved name", function()
			POST("/subreddit/create", { name = "all" }, "demo")
			assert.is_nil(Forum:find({ name = "all" }))
		end)
	end)

	describe("RSS output feeds", function()
		it("serves the frontpage feed as RSS XML", function()
			local status, body, headers = mock_request(app, "/.rss", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("<rss", 1, true))
			assert.truthy(body:find("<item>", 1, true))
			local ct = headers["content-type"] or headers.content_type or ""
			assert.truthy(ct:find("rss", 1, true))
		end)

		it("serves a subreddit feed and XML-escapes content", function()
			local u = Users:create({ user_name = "rss_user", user_pass = "password", user_email = "rss@e.com" })
			local f = Forum:create({ name = "rsssub", creator_id = u.id })
			Posts:create({ user_id = u.id, sub_id = f.id, title = "A & B <tag>", url = "https://ab.example" })

			local status, body = mock_request(app, "/r/rsssub/.rss", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("A &amp; B &lt;tag&gt;", 1, true))
		end)

		it("404s an unknown subreddit feed", function()
			local status = mock_request(app, "/r/nosuchsub/.rss", { method = "GET" })
			assert.same(404, status)
		end)
	end)

	describe("reply notifications", function()
		local Notifications = require("models.notifications")

		it("notifies the post author when someone comments", function()
			local op = Users:create({ user_name = "notif_op", user_pass = "password", user_email = "no@e.com" })
			Users:create({ user_name = "notif_replier", user_pass = "password", user_email = "nr@e.com" })
			local f = Forum:create({ name = "notifsub", creator_id = op.id })
			local p = Posts:create({ user_id = op.id, sub_id = f.id, title = "notif post", url = "https://n.example" })

			assert.same(0, Notifications:unread_count(op.id))
			POST("/post/" .. p.id .. "/comment", { body = "nice post" }, "notif_replier")
			assert.same(1, Notifications:unread_count(op.id))

			local list = Notifications:for_user(op.id)
			assert.same("post_reply", list[1].kind)
			assert.same("nice post", list[1].body)
		end)

		it("notifies the parent comment's author on a reply", function()
			local a = Users:create({ user_name = "notif_a", user_pass = "password", user_email = "na@e.com" })
			Users:create({ user_name = "notif_b", user_pass = "password", user_email = "nb@e.com" })
			local f = Forum:create({ name = "notifsub2", creator_id = a.id })
			local p = Posts:create({ user_id = a.id, sub_id = f.id, title = "np2", url = "https://n2.example" })
			local c = Comments:create({ post_id = p.id, user_id = a.id, body = "parent" })

			POST("/post/" .. p.id .. "/comment", { body = "a reply", parent_comment_id = tostring(c.id) }, "notif_b")
			assert.same(1, Notifications:unread_count(a.id))
			assert.same("comment_reply", Notifications:for_user(a.id)[1].kind)
		end)

		it("does not notify on a self-reply", function()
			local u = Users:create({ user_name = "notif_self", user_pass = "password", user_email = "ns@e.com" })
			local f = Forum:create({ name = "notifsub3", creator_id = u.id })
			local p = Posts:create({ user_id = u.id, sub_id = f.id, title = "np3", url = "https://n3.example" })

			POST("/post/" .. p.id .. "/comment", { body = "my own comment" }, "notif_self")
			assert.same(0, Notifications:unread_count(u.id))
		end)

		it("marks the inbox read when viewed", function()
			local op = Users:create({ user_name = "notif_read", user_pass = "password", user_email = "nrd@e.com" })
			Users:create({ user_name = "notif_reader2", user_pass = "password", user_email = "nr2@e.com" })
			local f = Forum:create({ name = "notifsub4", creator_id = op.id })
			local p = Posts:create({ user_id = op.id, sub_id = f.id, title = "np4", url = "https://n4.example" })
			POST("/post/" .. p.id .. "/comment", { body = "hi there" }, "notif_reader2")
			assert.same(1, Notifications:unread_count(op.id))

			local s, body = mock_request(app, "/inbox", { method = "GET", session = { current_user = "notif_read" } })
			assert.same(200, s)
			assert.truthy(body:find("hi there", 1, true))
			assert.same(0, Notifications:unread_count(op.id))
		end)
	end)

	describe("moderation", function()
		local Modlog = require("src.models.modlog")

		it("recognizes the subreddit creator and listed mods", function()
			local creator = Users:create({ user_name = "mod_creator", user_pass = "password", user_email = "mc@e.com" })
			local modu = Users:create({ user_name = "mod_user", user_pass = "password", user_email = "mu@e.com" })
			local other = Users:create({ user_name = "mod_other", user_pass = "password", user_email = "mo@e.com" })
			local f = Forum:create({ name = "modsub", creator_id = creator.id, moderator_ids = tostring(modu.id) })

			assert.is_true(Forum:can_moderate(creator.id, f))
			assert.is_true(Forum:can_moderate(modu.id, f))
			assert.is_false(Forum:can_moderate(other.id, f))
		end)

		it("lets a moderator remove a post (logged), hiding it from listings", function()
			local creator = Users:create({ user_name = "mod_creator2", user_pass = "password", user_email = "mc2@e.com" })
			local f = Forum:create({ name = "modsub2", creator_id = creator.id })
			local p = Posts:create({ user_id = creator.id, sub_id = f.id, title = "bad post", url = "https://b.example" })

			assert.same(302, (POST("/post/" .. p.id .. "/remove", {}, "mod_creator2")))
			assert.same(1, tonumber(Posts:find(p.id).locked))
			assert.same(0, #Posts:get_listing(f.id))
			assert.truthy(#Modlog:select("where post_id = ?", tostring(p.id)) >= 1)
		end)

		it("won't let a non-moderator remove", function()
			Users:create({ user_name = "not_mod", user_pass = "password", user_email = "nm@e.com" })
			local creator = Users:create({ user_name = "mod_creator3", user_pass = "password", user_email = "mc3@e.com" })
			local f = Forum:create({ name = "modsub3", creator_id = creator.id })
			local p = Posts:create({ user_id = creator.id, sub_id = f.id, title = "ok post", url = "https://o.example" })

			POST("/post/" .. p.id .. "/remove", {}, "not_mod")
			assert.same(0, tonumber(Posts:find(p.id).locked))
		end)
	end)

	describe("saved & hidden posts", function()
		local SavedPosts = require("models.saved_posts")
		local HiddenPosts = require("models.hidden_posts")

		it("saves/unsaves a post and lists it on /saved", function()
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "save me please", url = "https://sv.example" })
			assert.same(302, (POST("/post/" .. p.id .. "/save", {}, "demo")))
			assert.is_true(SavedPosts:is_saved(1, p.id))

			local s, body = mock_request(app, "/saved", { method = "GET", session = { current_user = "demo" } })
			assert.same(200, s)
			assert.truthy(body:find("save me please", 1, true))

			POST("/post/" .. p.id .. "/save", {}, "demo") -- toggle off
			assert.is_false(SavedPosts:is_saved(1, p.id))
		end)

		it("hides a post so it drops from a user's listing", function()
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "hide me", url = "https://hd.example" })
			POST("/post/" .. p.id .. "/hide", {}, "demo")
			assert.is_true(HiddenPosts:is_hidden(1, p.id))

			local hidden_filtered = {}
			for _, r in ipairs(Posts:get_listing({ exclude_hidden_for = 1 })) do hidden_filtered[r.id] = true end
			assert.is_nil(hidden_filtered[p.id])

			local unfiltered = {}
			for _, r in ipairs(Posts:get_listing({})) do unfiltered[r.id] = true end
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
			local old = Posts:create({ user_id = 1, sub_id = 1, title = "ancient", url = "https://o.example" })
			old:update({ created_at = "2000-01-01 00:00:00" })
			local recent = Posts:create({ user_id = 1, sub_id = 1, title = "fresh window", url = "https://f.example" })

			local since = require("src.utils.timewindow")("day")
			local ids = {}
			for _, r in ipairs(Posts:get_listing({ sub_id = 1, since = since })) do
				ids[r.id] = true
			end
			assert.is_nil(ids[old.id])
			assert.is_true(ids[recent.id])
		end)

		it("renders /r/:sub/top?t=week", function()
			local s = mock_request(app, "/r/programming/top", { method = "GET", get = { t = "week" } })
			assert.same(200, s)
		end)
	end)

	describe("pagination", function()
		local paginate = require("src.utils.paginate")

		it("slices items and reports metadata", function()
			local items = {}
			for i = 1, 30 do items[i] = i end

			local page1, info1 = paginate(items, 1, 25)
			assert.same(25, #page1)
			assert.is_true(info1.has_next)
			assert.is_false(info1.has_prev)

			local page2, info2 = paginate(items, 2, 25)
			assert.same(5, #page2)
			assert.same(26, page2[1])
			assert.is_false(info2.has_next)
			assert.is_true(info2.has_prev)
		end)

		it("paginates the frontpage over HTTP", function()
			for i = 1, 30 do
				Posts:create({ user_id = 1, sub_id = 1, title = "page post " .. i, url = "https://p" .. i .. ".example" })
			end
			local function PAGE(n)
				return mock_request(app, "/", { method = "GET", get = { page = tostring(n) } })
			end

			local s1, b1 = PAGE(1)
			assert.same(200, s1)
			assert.truthy(b1:find("page 1", 1, true)) -- page nav rendered

			local s2, b2 = PAGE(2)
			assert.same(200, s2)
			assert.truthy(b2:find("page 2", 1, true))
		end)
	end)

	describe("karma", function()
		it("sums votes on a user's posts and comments", function()
			local author = Users:create({ user_name = "karma_author", user_pass = "password", user_email = "k@e.com" })
			local v1 = Users:create({ user_name = "karma_v1", user_pass = "password", user_email = "k1@e.com" })
			local v2 = Users:create({ user_name = "karma_v2", user_pass = "password", user_email = "k2@e.com" })
			local p = Posts:create({ user_id = author.id, sub_id = 1, title = "karma post", url = "https://k.example" })
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
			return mock_request(app, "/search", { method = "GET", get = { q = q } })
		end

		it("finds posts by title and body, ranked, excluding non-matches", function()
			Posts:create({ user_id = 1, sub_id = 1, title = "Unique Zebra Headline", url = "https://z.example" })
			Posts:create({ user_id = 1, sub_id = 1, title = "plain title", body = "contains quokka here", is_self = 1 })

			local s1, body = SEARCH("Zebra")
			assert.same(200, s1)
			assert.truthy(body:find("Unique Zebra Headline", 1, true))

			local _, body2 = SEARCH("quokka") -- body match
			assert.truthy(body2:find("plain title", 1, true))

			local _, body3 = SEARCH("nonexistentxyzzy")
			assert.is_nil(body3:find("Unique Zebra Headline", 1, true))
		end)

		it("excludes deleted posts from search", function()
			local p = Posts:create({ user_id = 1, sub_id = 1, title = "Searchable Platypus", url = "https://p.example" })
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

			local s1, sub_body = mock_request(app, "/subscribed",
				{ method = "GET", session = { current_user = "demo" } })
			assert.same(200, s1)
			assert.truthy(sub_body:find("/r/programming", 1, true))

			-- the layout header shows "my subs" on any page when signed in
			local _, home = mock_request(app, "/",
				{ method = "GET", session = { current_user = "demo" } })
			assert.truthy(home:find("/r/programming", 1, true))

			POST("/subscribe/programming", {}, "demo") -- cleanup
		end)
	end)
end)

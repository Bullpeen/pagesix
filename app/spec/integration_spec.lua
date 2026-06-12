--- Integration spec: drives the real app through mock_request (routing,
--- actions, auth/session, redirects, rendering) for each feature.

local use_test_env = require("lapis.spec").use_test_env
local mock_request = require("lapis.spec.request").mock_request

describe("pagesix integration", function()
	use_test_env()

	local migrations = require("migrations")
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
		it("logs in with valid credentials", function()
			local status = POST("/login", { username = "demo", password = "password" })
			assert.same(302, status)
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

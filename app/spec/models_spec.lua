--- Model relation + schema spec
-- Runs the schema-creating migrations against an in-memory SQLite database
-- (LAPIS_ENV=test) and exercises the model relations that the actions rely on.

local use_test_env = require("lapis.spec").use_test_env

describe("pagesix models", function()
	use_test_env()

	local Sort = require("src.utils.sort")
	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Subscriptions = require("models.subscriptions")
	local Votes = require("src.models.votes")

	setup(function()
		-- Only the schema-creating migrations; skip the seed/RSS/sample-data
		-- migrations (13+), which need external files and network access.
		require("spec.schema_helper")()
	end)

	local function make_user(name)
		return Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
	end

	it("resolves a post's author, subreddit, and comments", function()
		local author = make_user("alice")
		local sub = Forum:create({ name = "programming", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "Hello world",
			url = "https://example.com",
		})
		Comments:create({ post_id = post.id, user_id = author.id, body = "first!" })

		assert.same("alice", post:get_user().user_name)
		assert.same(sub.id, post:get_subreddit().id)

		local comments = post:get_comments()
		assert.same(1, #comments)
		-- comments.user is belongs_to (was has_one, which resolved to nil).
		assert.same("alice", comments[1]:get_user().user_name)
	end)

	it("resolves a subscription's subreddit via the forum table", function()
		local user = make_user("bob")
		local sub = Forum:create({ name = "science", creator_id = user.id })
		local subscription = Subscriptions:create({
			user_id = user.id,
			subreddit_id = sub.id,
		})

		-- belongs_to "Forum" (was "Subreddits", a model that does not exist).
		assert.same("science", subscription:get_subreddit().name)
	end)

	it("exposes a user's own posts and comments", function()
		local user = make_user("carol")
		local sub = Forum:create({ name = "books", creator_id = user.id })
		local post = Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = "A book",
			url = "https://b.example",
		})
		Comments:create({ post_id = post.id, user_id = user.id, body = "good read" })

		assert.same(1, #user:get_posts())
		assert.same(1, #user:get_comments())
	end)

	it("builds a real permalink from Posts:url_params", function()
		local user = make_user("dave")
		local sub = Forum:create({ name = "news", creator_id = user.id })
		local post = Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = "Big News Today",
			url = "https://n.example",
		})

		local route, params = post:url_params()
		assert.same("post", route)
		assert.same("news", params.subreddit)
		assert.same(post.id, params.post_id)
		assert.same("big_news_today", params.title_stub)
	end)

	it("get_listing aggregates votes/comments and enriches each row", function()
		local author = make_user("erin")
		local v1 = make_user("voter1")
		local v2 = make_user("voter2")
		local sub = Forum:create({ name = "movies", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "Cool Movie",
			url = "https://example.com/film",
		})
		-- 2 upvotes, 1 downvote (one vote per user per post), 1 comment.
		Votes:create({ user_id = author.id, post_id = post.id, upvote = 1 })
		Votes:create({ user_id = v1.id, post_id = post.id, upvote = 1 })
		Votes:create({ user_id = v2.id, post_id = post.id, upvote = 0 })
		Comments:create({ post_id = post.id, user_id = author.id, body = "nice" })

		-- Scope to this subreddit: use_test_env does not roll back SQLite rows
		-- between examples, so the global table accumulates across tests.
		local listing = Posts:get_listing(sub.id)
		assert.same(1, #listing)
		local row = listing[1]
		assert.same(2, tonumber(row.upvotes))
		assert.same(1, tonumber(row.downvotes))
		assert.same(1, tonumber(row.num_comments))
		assert.same("erin", row.author)
		assert.same("/r/movies/comments/" .. post.id, row.permalink)
		assert.same("example.com", row.domain)
	end)

	it("get_listing lists zero-vote posts and filters by subreddit", function()
		local user = make_user("frank")
		local a = Forum:create({ name = "gaming", creator_id = user.id })
		local b = Forum:create({ name = "history", creator_id = user.id })
		Posts:create({
			user_id = user.id,
			sub_id = a.id,
			title = "no votes yet",
			url = "https://x.example",
		})
		Posts:create({
			user_id = user.id,
			sub_id = b.id,
			title = "other sub",
			url = "https://y.example",
		})

		local only_a = Posts:get_listing(a.id)
		assert.same(1, #only_a)
		assert.same("gaming", only_a[1].subreddit)
		assert.same(0, tonumber(only_a[1].upvotes)) -- zero-vote post still listed
		assert.same(1, #Posts:get_listing(b.id))
	end)

	it("rejects a reserved username (seeded in migration [2])", function()
		-- 'admin' is seeded into reserved_usernames; the user_name constraint
		-- blocks it and Users:create returns nil + the error message.
		local user, err = Users:create({
			user_name = "admin",
			user_pass = "password",
			user_email = "admin@example.com",
		})
		assert.is_nil(user)
		assert.same("Username is reserved", err)
		-- A non-reserved name still works.
		assert.is_truthy(make_user("grace"))
	end)

	it("get_listing filters by link domain", function()
		local user = make_user("heidi")
		local sub = Forum:create({ name = "technology", creator_id = user.id })
		Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = "on github",
			url = "https://github.com/a/b",
		})
		Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = "elsewhere",
			url = "https://example.org/x",
		})

		local gh = Posts:get_listing({ domain = "github.com" })
		assert.same(1, #gh)
		assert.same("on github", gh[1].title)
		assert.same("github.com", gh[1].domain)
	end)

	it("Sort orders by 'top' and tolerates rows missing vote fields", function()
		local rows = {
			{ id = 1, upvotes = 1, downvotes = 0 },
			{ id = 2, upvotes = 9, downvotes = 1 },
			{ id = 3 }, -- missing upvotes/downvotes -> treated as 0, must not error
		}
		local sorted = Sort:sort(rows, "top")
		assert.same(2, sorted[1].id) -- score 8
		assert.same(1, sorted[2].id) -- score 1
		assert.same(3, sorted[3].id) -- score 0
	end)
end)

--- Model relation + schema spec
-- Runs the schema-creating migrations against an in-memory SQLite database
-- (LAPIS_ENV=test) and exercises the model relations that the actions rely on.

local use_test_env = require("lapis.spec").use_test_env

describe("pagesix models", function()
	use_test_env()

	local migrations = require("migrations")
	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Subscriptions = require("models.subscriptions")

	setup(function()
		-- Only the schema-creating migrations; skip the seed/RSS/sample-data
		-- migrations (13+), which need external files and network access.
		migrations[1]() -- pragmas
		migrations[2]() -- users, user_profiles, subscriptions, reserved_usernames
		migrations[3]() -- forum
		migrations[4]() -- posts, comments, votes, modlog, views
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
end)

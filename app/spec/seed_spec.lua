--- Seed-migration spec
-- Exercises the data-generating migrations ([14]/[15]/[20]/[30]/[40]) against
-- an in-memory database and asserts they run without crashing and never leave
-- rows whose foreign keys point at nothing. (RSS migration [16] is skipped:
-- it hits the network.)

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("seed migrations", function()
	use_test_env()

	local migrations = require("migrations")
	local Users = require("models.users")
	local Forum = require("src.models.forum")

	setup(function()
		require("spec.schema_helper")()

		-- Prerequisites the seed steps assume: at least one user and some subs.
		Users:create({ user_name = "seed_anon", user_pass = "password", user_email = "a@e.com" })
		for _, name in ipairs({ "seed_alpha", "seed_beta", "seed_gamma" }) do
			Forum:create({ name = name, creator_id = 1 })
		end
	end)

	local function count(sql)
		return tonumber(db.select(sql)[1].c)
	end

	it("[14] subscribes real users to real subreddits (no orphan FKs)", function()
		migrations[14]()
		assert.same(
			0,
			count([[COUNT(*) AS c FROM subscriptions s
			LEFT JOIN users u ON s.user_id = u.id WHERE u.id IS NULL]])
		)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM subscriptions s
			LEFT JOIN forum f ON s.subreddit_id = f.id WHERE f.id IS NULL]])
		)
	end)

	it("[15] creates posts attached to real subreddits and users", function()
		migrations[15]()
		assert.truthy(count([[COUNT(*) AS c FROM posts]]) > 0)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM posts a
			LEFT JOIN forum f ON a.sub_id = f.id WHERE f.id IS NULL]])
		)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM posts a
			LEFT JOIN users u ON a.user_id = u.id WHERE u.id IS NULL]])
		)
	end)

	it("[20]/[30]/[40] seed votes and comments without orphans or crashes", function()
		migrations[20]() -- votes on posts
		migrations[30]() -- comments
		migrations[40]() -- votes on comments

		assert.truthy(count([[COUNT(*) AS c FROM votes]]) > 0)
		assert.truthy(count([[COUNT(*) AS c FROM comments]]) > 0)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM votes v
			LEFT JOIN posts p ON v.post_id = p.id WHERE p.id IS NULL]])
		)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM votes v
			LEFT JOIN users u ON v.user_id = u.id WHERE u.id IS NULL]])
		)
		assert.same(
			0,
			count([[COUNT(*) AS c FROM comments c
			LEFT JOIN posts p ON c.post_id = p.id WHERE p.id IS NULL]])
		)
	end)
end)

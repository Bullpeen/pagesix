--- User reputation spec: recompute matches live karma, persists to the cached
--- column, trust-level thresholds, the [102] backfill, and the vote-action wiring.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("user reputation", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Votes = require("src.models.votes")
	local migrations = require("migrations")
	local app = require("app")

	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	setup(function()
		require("spec.schema_helper")()
	end)

	local function make_user(name)
		return Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
	end

	it("trust_level maps reputation to bands (boundaries inclusive)", function()
		assert.same("new", Users:trust_level(0))
		assert.same("new", Users:trust_level(9))
		assert.same("member", Users:trust_level(10))
		assert.same("member", Users:trust_level(99))
		assert.same("trusted", Users:trust_level(100))
		assert.same("trusted", Users:trust_level(249))
		assert.same("veteran", Users:trust_level(250))
		-- nil / negative tolerated
		assert.same("new", Users:trust_level(nil))
		assert.same("new", Users:trust_level(-5))
	end)

	it("recompute_reputation matches karma and persists to the column", function()
		local author = make_user("rep_author")
		local v1 = make_user("rep_v1")
		local v2 = make_user("rep_v2")
		local sub = Forum:create({ name = "rep_sub", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "rep post",
			url = "https://e.example",
		})
		Votes:create({ user_id = v1.id, post_id = post.id, upvote = 1 })
		Votes:create({ user_id = v2.id, post_id = post.id, upvote = 1 })

		local rep = Users:recompute_reputation(author.id)
		assert.same(2, rep)
		assert.same(Users:karma(author.id), rep)
		assert.same(2, tonumber(Users:find(author.id).reputation))
	end)

	it("a downvote lowers the persisted reputation", function()
		local author = make_user("rep_author2")
		local voter = make_user("rep_down")
		local sub = Forum:create({ name = "rep_sub2", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "rep post 2",
			url = "https://e2.example",
		})
		Votes:create({ user_id = voter.id, post_id = post.id, upvote = 0 })
		assert.same(-1, Users:recompute_reputation(author.id))
	end)

	it("migration [102] backfills reputation from existing votes", function()
		local author = make_user("rep_backfill")
		local voter = make_user("rep_bf_voter")
		local sub = Forum:create({ name = "rep_bf_sub", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "bf",
			url = "https://bf.example",
		})
		Votes:create({ user_id = voter.id, post_id = post.id, upvote = 1 })
		-- Re-running the migration recomputes every user's reputation column.
		migrations[102]()
		assert.same(1, tonumber(Users:find(author.id).reputation))
	end)

	it("voting through the action updates the author's reputation", function()
		local author = make_user("rep_voted_on")
		make_user("rep_voter_ui") -- the voter signs in via the session below
		local sub = Forum:create({ name = "rep_ui_sub", creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "ui vote",
			url = "https://ui.example",
		})

		simulate_request(app, "/vote/post/" .. post.id .. "/up", {
			method = "POST",
			post = { csrf_token = CSRF_TOKEN },
			session = { current_user = "rep_voter_ui" },
			cookies = { [CSRF_COOKIE] = CSRF_KEY },
		})

		assert.same(1, tonumber(Users:find(author.id).reputation))
	end)
end)

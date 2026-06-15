--- Approval-queue spec: holding policy, rate limiting, visibility filtering,
--- and the moderator review flow (access control + approve/reject + modlog).

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("approval queue", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Modlog = require("src.models.modlog")
	local Queue = require("src.utils.queue")
	local Ratelimit = require("src.utils.ratelimit")
	local app = require("app")

	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	local function GET(url, user)
		return simulate_request(app, url, {
			method = "GET",
			session = user and { current_user = user } or nil,
		})
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

	-- A user with enough reputation to clear the "new" trust band.
	local function make_user(name, reputation)
		local u = Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
		if reputation then
			u:update({ reputation = reputation })
		end
		return u
	end

	local owner, newbie, established, sub
	setup(function()
		require("spec.schema_helper")()
		owner = make_user("q_owner")
		newbie = make_user("q_newbie") -- reputation 0 -> trust "new"
		established = make_user("q_estab", 25) -- trust "member"
		sub = Forum:create({ name = "q_sub", creator_id = owner.id })
		Forum:add_owner(sub.id, owner.id)
	end)

	describe("holding policy", function()
		it("holds brand-new users but not established ones", function()
			assert.is_true(Queue.should_hold(newbie, sub))
			assert.is_false(Queue.should_hold(established, sub))
		end)

		it("never holds the forum owner/moderators", function()
			assert.is_false(Queue.should_hold(owner, sub))
			local mod = make_user("q_mod") -- new account...
			Forum:add_moderator(sub.id, mod.id) -- ...but a moderator here
			assert.is_false(Queue.should_hold(mod, sub))
		end)
	end)

	describe("rate limiting", function()
		it("trips once the per-window count is reached", function()
			local u = make_user("q_rl", 50)
			local s = Forum:create({ name = "q_rl_sub", creator_id = owner.id })
			for i = 1, 3 do
				Posts:create({
					user_id = u.id,
					sub_id = s.id,
					title = "rl " .. i,
					url = "https://rl.example/" .. i,
				})
			end
			assert.is_true(Ratelimit.exceeded("posts", u.id, 3, 600))
			assert.is_false(Ratelimit.exceeded("posts", u.id, 4, 600))
		end)
	end)

	describe("visibility", function()
		it("hides held posts from listings but shows approved ones", function()
			local pending = Posts:create({
				user_id = newbie.id,
				sub_id = sub.id,
				title = "held post",
				url = "https://h.example",
				approved = 0,
			})
			local visible = Posts:create({
				user_id = established.id,
				sub_id = sub.id,
				title = "visible post",
				url = "https://v.example",
				approved = 1,
			})
			local titles = {}
			for _, row in ipairs(Posts:get_listing(sub.id)) do
				titles[row.title] = true
			end
			assert.is_nil(titles["held post"])
			assert.is_true(titles["visible post"])
			-- the held post's own page bounces an anonymous viewer home
			assert.same(302, (GET("/r/q_sub/comments/" .. pending.id)))
			-- but the author may see it
			assert.same(200, (GET("/r/q_sub/comments/" .. pending.id, "q_newbie")))
			assert.same(200, (GET("/r/q_sub/comments/" .. visible.id)))
		end)

		it("hides held comments from the thread", function()
			local post = Posts:create({
				user_id = established.id,
				sub_id = sub.id,
				title = "thread host",
				url = "https://t.example",
			})
			Comments:create({
				post_id = post.id,
				user_id = newbie.id,
				body = "held comment",
				approved = 0,
			})
			Comments:create({
				post_id = post.id,
				user_id = established.id,
				body = "shown comment",
				approved = 1,
			})
			local bodies = {}
			for _, c in ipairs(Comments:thread(post.id)) do
				bodies[c.body] = true
			end
			assert.is_nil(bodies["held comment"])
			assert.is_true(bodies["shown comment"])
		end)
	end)

	describe("submit action", function()
		it("holds a new user's submitted post", function()
			POST("/submit", {
				subreddit = "q_sub",
				title = "newbie submission",
				url = "https://ns.example",
			}, "q_newbie")
			local post = Posts:find({ title = "newbie submission" })
			assert.is_truthy(post)
			assert.same(0, tonumber(post.approved))
		end)

		it("publishes an established user's post immediately", function()
			POST("/submit", {
				subreddit = "q_sub",
				title = "estab submission",
				url = "https://es.example",
			}, "q_estab")
			local post = Posts:find({ title = "estab submission" })
			assert.is_truthy(post)
			assert.same(1, tonumber(post.approved))
		end)
	end)

	describe("queue review", function()
		it("forbids anonymous and non-moderators", function()
			assert.same(302, (GET("/r/q_sub/queue")))
			assert.same(403, (GET("/r/q_sub/queue", "q_estab")))
		end)

		it("lets a moderator view, approve, and reject", function()
			assert.same(200, (GET("/r/q_sub/queue", "q_owner")))

			local approved_post = Posts:create({
				user_id = newbie.id,
				sub_id = sub.id,
				title = "to approve",
				url = "https://app.example",
				approved = 0,
			})
			local rejected_post = Posts:create({
				user_id = newbie.id,
				sub_id = sub.id,
				title = "to reject",
				url = "https://rej.example",
				approved = 0,
			})

			POST(
				"/r/q_sub/queue",
				{ kind = "post", id = approved_post.id, op = "approve" },
				"q_owner"
			)
			POST(
				"/r/q_sub/queue",
				{ kind = "post", id = rejected_post.id, op = "reject" },
				"q_owner"
			)

			local approved = Posts:find(approved_post.id)
			assert.same(1, tonumber(approved.approved))
			assert.same(0, tonumber(approved.deleted))

			local rejected = Posts:find(rejected_post.id)
			assert.same(1, tonumber(rejected.deleted)) -- rejected = soft-deleted

			-- both decisions are recorded in the modlog
			local entries = Modlog:for_subreddit(sub.id)
			local reasons = {}
			for _, e in ipairs(entries) do
				reasons[e.reason] = true
			end
			assert.is_true(reasons["approved post (queue)"])
			assert.is_true(reasons["rejected post (queue)"])
		end)

		it("ignores a queue POST from a non-moderator (403, no change)", function()
			local held = Posts:create({
				user_id = newbie.id,
				sub_id = sub.id,
				title = "still held",
				url = "https://sh.example",
				approved = 0,
			})
			assert.same(
				403,
				(POST("/r/q_sub/queue", { kind = "post", id = held.id, op = "approve" }, "q_estab"))
			)
			assert.same(0, tonumber(Posts:find(held.id).approved))
		end)
	end)
end)

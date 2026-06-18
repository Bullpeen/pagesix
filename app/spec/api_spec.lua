--- API spec: drives the JSON API through simulate_request (routing, auth/CSRF,
--- serialization) and asserts the Reddit-flavoured Thing/Listing envelopes.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request
local cjson = require("cjson")

describe("api", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local S = require("src.utils.api_serialize")
	local app = require("app")

	-- Same CSRF trick as integration_spec: one (cookie, token) pair valid for
	-- every POST (the global before_filter only checks the token against the
	-- cookie, and accepts it from the csrf_token param).
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
	local function body_of(url, user)
		local status, body = GET(url, user)
		return status, cjson.decode(body)
	end
	-- Decode a (status, body) POST result: `body_of_post(POST(...))`.
	local function body_of_post(status, body)
		return status, cjson.decode(body)
	end

	local sub, post, comment, demo

	setup(function()
		require("spec.schema_helper")()
		demo =
			Users:create({ user_name = "apidemo", user_pass = "password", user_email = "a@e.com" })
		sub = Forum:create({ name = "apisub", creator_id = demo.id, description = "API sub" })
		-- Make the author a moderator so submit/comment posts aren't held in the
		-- new-user approval queue (mirrors integration_spec's flair_user).
		Forum:add_moderator(sub.id, demo.id)
		post = Posts:create({
			user_id = demo.id,
			sub_id = sub.id,
			title = "API Hello",
			url = "https://api.example.com/x",
		})
		comment =
			Comments:create({ post_id = post.id, user_id = demo.id, body = "api comment one" })
	end)

	describe("listings", function()
		it("serves the frontpage listing as Things", function()
			local status, json = body_of("/api/listing")
			assert.same(200, status)
			assert.same("Listing", json.kind)
			assert.truthy(#json.data.children > 0)
			assert.same("t3", json.data.children[1].kind)
			local found
			for _, c in ipairs(json.data.children) do
				if c.data.title == "API Hello" then
					found = c
				end
			end
			assert.truthy(found)
			assert.same(S.fullname("link", post.id), found.data.name)
			assert.same("api.example.com", found.data.domain)
			assert.truthy(found.data.uuid)
		end)

		it("accepts a sort segment", function()
			assert.same(200, (GET("/api/listing/top")))
			assert.same(200, (GET("/api/listing/new")))
		end)

		it("serves a subreddit listing", function()
			local status, json = body_of("/api/r/apisub")
			assert.same(200, status)
			assert.same("Listing", json.kind)
		end)

		it("404s an unknown subreddit listing", function()
			assert.same(404, (GET("/api/r/nope")))
		end)
	end)

	describe("about / lookup", function()
		it("returns a subreddit Thing (literal about beats the sort route)", function()
			local status, json = body_of("/api/r/apisub/about")
			assert.same(200, status)
			assert.same("t5", json.kind)
			assert.same("apisub", json.data.display_name)
			assert.same("r/apisub", json.data.display_name_prefixed)
		end)

		it("returns an account Thing", function()
			local status, json = body_of("/api/user/apidemo/about")
			assert.same(200, status)
			assert.same("t2", json.kind)
			assert.same("apidemo", json.data.name)
		end)

		it("resolves fullnames via /api/info", function()
			local ids = S.fullname("link", post.id) .. "," .. S.fullname("comment", comment.id)
			local status, json = body_of("/api/info?id=" .. ids)
			assert.same(200, status)
			assert.same(2, #json.data.children)
			assert.same("t3", json.data.children[1].kind)
			assert.same("t1", json.data.children[2].kind)
		end)

		it("reports username availability", function()
			local _, taken = body_of("/api/username_available?user=apidemo")
			assert.same(false, taken.available)
			local _, free = body_of("/api/username_available?user=totallyfreename")
			assert.same(true, free.available)
			local _, reserved = body_of("/api/username_available?user=admin")
			assert.same(false, reserved.available)
		end)
	end)

	describe("comments tree", function()
		it("returns [link, comments] with the comment nested", function()
			local status, json = body_of("/api/comments/" .. post.id)
			assert.same(200, status)
			assert.same("Listing", json[1].kind)
			assert.same("t3", json[1].data.children[1].kind)
			assert.same("Listing", json[2].kind)
			local bodies = {}
			for _, c in ipairs(json[2].data.children) do
				bodies[c.data.body] = true
			end
			assert.truthy(bodies["api comment one"])
		end)
	end)

	describe("search", function()
		it("finds posts via FTS", function()
			local status, json = body_of("/api/search?q=Hello")
			assert.same(200, status)
			assert.same("Listing", json.kind)
			assert.truthy(#json.data.children > 0)
		end)

		it("finds subreddits by name", function()
			local status, json = body_of("/api/subreddits/search?q=apisub")
			assert.same(200, status)
			assert.same("t5", json.data.children[1].kind)
		end)

		it("lists the subreddit directory", function()
			local status, json = body_of("/api/subreddits")
			assert.same(200, status)
			assert.same("Listing", json.kind)
		end)
	end)

	describe("account (auth)", function()
		it("401s /api/v1/me when logged out", function()
			assert.same(401, (GET("/api/v1/me")))
		end)

		it("returns the current account", function()
			local status, json = body_of("/api/v1/me", "apidemo")
			assert.same(200, status)
			assert.same("apidemo", json.name)
			assert.truthy(json.uuid)
		end)

		it("returns a karma breakdown", function()
			local status, json = body_of("/api/v1/me/karma", "apidemo")
			assert.same(200, status)
			assert.same("KarmaList", json.kind)
			assert.truthy(json.data[1])
		end)
	end)

	describe("vote (auth)", function()
		it("401s without a session", function()
			assert.same(401, (POST("/api/vote", { id = S.fullname("link", post.id), dir = 1 })))
		end)

		it("rejects a bad dir", function()
			assert.same(
				400,
				(POST("/api/vote", { id = S.fullname("link", post.id), dir = 5 }, "apidemo"))
			)
		end)

		it("casts and clears an explicit post vote", function()
			local p = Posts:create({
				user_id = demo.id,
				sub_id = sub.id,
				title = "votable",
				url = "https://v.example",
			})
			local fn = S.fullname("link", p.id)
			local _, up = body_of_post(POST("/api/vote", { id = fn, dir = 1 }, "apidemo"))
			assert.same(1, Votes:post_score(p.id))
			POST("/api/vote", { id = fn, dir = 0 }, "apidemo")
			assert.same(0, Votes:post_score(p.id))
			assert.truthy(up)
		end)
	end)

	describe("save / hide (auth)", function()
		it("saves then lists then unsaves", function()
			local fn = S.fullname("link", post.id)
			assert.same(200, (POST("/api/save", { id = fn }, "apidemo")))
			local _, saved = body_of("/api/me/saved", "apidemo")
			local titles = {}
			for _, c in ipairs(saved.data.children) do
				titles[c.data.title] = true
			end
			assert.truthy(titles["API Hello"])
			assert.same(200, (POST("/api/unsave", { id = fn }, "apidemo")))
		end)

		it("hides a post from the owner's listing", function()
			local p = Posts:create({
				user_id = demo.id,
				sub_id = sub.id,
				title = "HIDE_ME_TITLE",
				url = "https://h.example",
			})
			POST("/api/hide", { id = S.fullname("link", p.id) }, "apidemo")
			local _, json = body_of("/api/listing", "apidemo")
			for _, c in ipairs(json.data.children) do
				assert.not_same("HIDE_ME_TITLE", c.data.title)
			end
		end)
	end)

	describe("subscribe (auth)", function()
		it("subscribes and unsubscribes", function()
			local fn = S.fullname("subreddit", sub.id)
			POST("/api/subscribe", { sr = fn, action = "sub" }, "apidemo")
			local Subscriptions = require("models.subscriptions")
			assert.truthy(Subscriptions:is_subscribed(demo.id, sub.id))
			POST("/api/subscribe", { sr_name = "apisub", action = "unsub" }, "apidemo")
			assert.falsy(Subscriptions:is_subscribed(demo.id, sub.id))
		end)
	end)

	describe("submit / comment / edit / del (auth)", function()
		it("submits a self post", function()
			local status, json = body_of_post(POST("/api/submit", {
				sr = "apisub",
				kind = "self",
				title = "Submitted via API",
				text = "hello body",
			}, "apidemo"))
			assert.same(201, status)
			assert.same("t3", json.thing.kind)
			assert.same("Submitted via API", json.thing.data.title)
			assert.is_true(json.thing.data.is_self)
		end)

		it("comments on a post", function()
			local status, json = body_of_post(POST("/api/comment", {
				parent = S.fullname("link", post.id),
				text = "a fresh api reply",
			}, "apidemo"))
			assert.same(201, status)
			assert.same("t1", json.thing.kind)
			assert.same("a fresh api reply", json.thing.data.body)
		end)

		it("edits and deletes own post", function()
			local p = Posts:create({
				user_id = demo.id,
				sub_id = sub.id,
				title = "editable",
				body = "old",
				is_self = 1,
			})
			local fn = S.fullname("link", p.id)
			assert.same(
				200,
				(POST("/api/editusertext", { thing_id = fn, text = "new body" }, "apidemo"))
			)
			assert.same("new body", Posts:find(p.id).body)
			assert.same(200, (POST("/api/del", { id = fn }, "apidemo")))
			assert.same(1, tonumber(Posts:find(p.id).deleted))
		end)
	end)
end)

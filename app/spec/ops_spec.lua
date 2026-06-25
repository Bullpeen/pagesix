--- Integration spec for the ops + dashboard endpoints: /health, /metrics, the
--- admin stats page, and the mod-gated per-subreddit stats page.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request
local cjson = require("cjson")

describe("ops + dashboards", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local SiteRoles = require("src.models.site_roles")
	local app = require("app")

	local function GET(url, user)
		return simulate_request(app, url, {
			method = "GET",
			session = user and { current_user = user } or nil,
		})
	end

	setup(function()
		require("spec.schema_helper")()
		local boss =
			Users:create({ user_name = "opsboss", user_pass = "password", user_email = "b@e.com" })
		SiteRoles:grant(boss.id, "admin")
		local modu =
			Users:create({ user_name = "opsmod", user_pass = "password", user_email = "m@e.com" })
		Users:create({ user_name = "opspleb", user_pass = "password", user_email = "p@e.com" })
		local sub = Forum:create({ name = "opssub", creator_id = boss.id, description = "ops" })
		Forum:add_moderator(sub.id, modu.id)
		Posts:create({
			user_id = boss.id,
			sub_id = sub.id,
			title = "ops post",
			url = "https://o.example",
		})
	end)

	describe("/health", function()
		it("returns ok JSON with a 200", function()
			local status, body = GET("/health")
			assert.same(200, status)
			local json = cjson.decode(body)
			assert.same("ok", json.status)
			assert.same("ok", json.db)
		end)
	end)

	describe("/metrics", function()
		it("serves Prometheus exposition", function()
			local status, body = GET("/metrics")
			assert.same(200, status)
			assert.truthy(body:find("pagesix_posts", 1, true))
			assert.truthy(body:find("# TYPE pagesix_up gauge", 1, true))
		end)
	end)

	describe("/admin/stats", function()
		it("redirects anonymous users", function()
			assert.same(302, (GET("/admin/stats")))
		end)

		it("forbids non-admins", function()
			assert.same(403, (GET("/admin/stats", "opspleb")))
		end)

		it("renders charts for an admin", function()
			local status, body = GET("/admin/stats", "opsboss")
			assert.same(200, status)
			assert.truthy(body:find("Top subreddits", 1, true))
			assert.truthy(body:find("<svg", 1, true))
		end)
	end)

	describe("/r/:sub/stats", function()
		it("redirects anonymous users to login", function()
			assert.same(302, (GET("/r/opssub/stats")))
		end)

		it("forbids non-moderators", function()
			assert.same(403, (GET("/r/opssub/stats", "opspleb")))
		end)

		it("renders charts for a moderator", function()
			local status, body = GET("/r/opssub/stats", "opsmod")
			assert.same(200, status)
			assert.truthy(body:find("Top contributors", 1, true))
			assert.truthy(body:find("<svg", 1, true))
		end)
	end)
end)

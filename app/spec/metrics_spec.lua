--- Spec for utils/metrics: the Prometheus text exposition.

local use_test_env = require("lapis.spec").use_test_env

describe("metrics", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local metrics = require("src.utils.metrics")

	setup(function()
		require("spec.schema_helper")()
		local u =
			Users:create({ user_name = "mxuser", user_pass = "password", user_email = "m@e.com" })
		local f = Forum:create({ name = "mxsub", creator_id = u.id })
		Posts:create({ user_id = u.id, sub_id = f.id, title = "p", url = "https://m.example" })
	end)

	it("emits gauges in Prometheus exposition format", function()
		local body = metrics.render()
		assert.truthy(body:find("# HELP pagesix_up", 1, true))
		assert.truthy(body:find("# TYPE pagesix_users gauge", 1, true))
		assert.truthy(body:match("pagesix_up 1"))
		assert.truthy(body:match("pagesix_posts %d"))
		assert.truthy(body:match("pagesix_comments %d"))
	end)

	it("omits HTTP counters with no shared dict (and observe is a no-op)", function()
		assert.is_nil(metrics.http_requests())
		assert.has_no.errors(function()
			metrics.observe(200)
		end)
		assert.is_nil(metrics.render():find("pagesix_http_requests_total", 1, true))
	end)
end)

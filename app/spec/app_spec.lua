--- Spec file for app.lua
-- @script app_spec

local mock_request = require("lapis.spec.request").mock_request
local app = require("app")

describe("readit", function()
	require("lapis.spec").use_test_env()

	setup(function()
		require("lapis.db.migrations").run_migrations(require("migrations"))
	end)

	it("loads install page", function()
		local status, body = mock_request(app, "/")
		assert.same(200, status)
		assert.truthy(body:find("Install Readit", 1, true))
	end)
end)

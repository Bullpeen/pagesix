--- Unit spec for utils/uuid: the API's stable external-id generator.

local use_test_env = require("lapis.spec").use_test_env

describe("uuid", function()
	-- Loads sqlite_ext + lapis.db so the preferred sqlean uuid4() path is exercised
	-- when the extension is available (with the openssl/math fallbacks otherwise).
	use_test_env()

	local uuid = require("src.utils.uuid")

	local V4 = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

	it("generates a canonical v4 UUID", function()
		local u = uuid.generate()
		assert.same(36, #u)
		assert.truthy(u:match(V4), "not a v4 uuid: " .. u)
	end)

	it("generates distinct values", function()
		local seen = {}
		for _ = 1, 25 do
			local u = uuid.generate()
			assert.is_nil(seen[u])
			seen[u] = true
		end
	end)

	it("falls back to a formatted v4 when sqlean is unavailable", function()
		-- Force the non-sqlean path (test/lint envs without the .so) by stubbing
		-- the extension loader to report "not loaded", then re-requiring uuid.
		local saved_ext = package.loaded["src.utils.sqlite_ext"]
		package.loaded["src.utils.sqlite_ext"] = {
			load = function()
				return false
			end,
		}
		package.loaded["src.utils.uuid"] = nil
		local fresh = require("src.utils.uuid")

		local u = fresh.generate()

		package.loaded["src.utils.sqlite_ext"] = saved_ext
		package.loaded["src.utils.uuid"] = uuid

		assert.same(36, #u)
		assert.truthy(u:match(V4), "not a v4 uuid: " .. u)
	end)
end)

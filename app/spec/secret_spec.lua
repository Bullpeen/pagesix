--- utils.secret spec
-- The boot-time guard on the session/CSRF signing key. `getenv` is injected so
-- these never depend on the environment the suite happens to run in.

describe("utils.secret", function()
	local secret = require("src.utils.secret")

	-- Build a getenv stand-in over a plain table.
	local function env(vars)
		return function(name)
			return vars[name]
		end
	end

	describe("resolve", function()
		it("prefers SESSION_SECRET over the older LAPIS_SECRET", function()
			local got = secret.resolve("production", "production", {
				getenv = env({ SESSION_SECRET = "new", LAPIS_SECRET = "old" }),
			})
			assert.same("new", got)
		end)

		it("still accepts LAPIS_SECRET on its own", function()
			local got = secret.resolve("production", "production", {
				getenv = env({ LAPIS_SECRET = "old" }),
			})
			assert.same("old", got)
		end)

		it("refuses to start the active environment with no secret", function()
			local ok, err = pcall(secret.resolve, "production", "production", {
				getenv = env({}),
			})
			assert.is_false(ok)
			-- The message has to name the variable an operator should set.
			assert.truthy(tostring(err):find("SESSION_SECRET", 1, true))
			assert.truthy(tostring(err):find("production", 1, true))
		end)

		it("treats an empty value as unset", function()
			-- `fly secrets set SESSION_SECRET=` and friends produce "", which
			-- would otherwise sign every cookie with the empty string.
			local ok = pcall(secret.resolve, "production", "production", {
				getenv = env({ SESSION_SECRET = "", LAPIS_SECRET = "" }),
			})
			assert.is_false(ok)
		end)

		it("leaves an inactive environment's block alone", function()
			-- config.lua evaluates every block on every boot; booting in
			-- development must not trip the production block's guard.
			local got = secret.resolve("production", "development", { getenv = env({}) })
			assert.is_nil(got)
		end)

		it("uses the fallback when one is offered", function()
			local got = secret.resolve("development", "development", {
				getenv = env({}),
				fallback = "dev-insecure",
			})
			assert.same("dev-insecure", got)
		end)

		it("prefers a real secret over the fallback", function()
			local got = secret.resolve("development", "development", {
				getenv = env({ SESSION_SECRET = "actual" }),
				fallback = "dev-insecure",
			})
			assert.same("actual", got)
		end)
	end)

	describe("active_env", function()
		it("reads LAPIS_ENV", function()
			assert.same("production", secret.active_env(env({ LAPIS_ENV = "production" })))
		end)

		it("defaults to development when unset or blank", function()
			assert.same("development", secret.active_env(env({})))
			assert.same("development", secret.active_env(env({ LAPIS_ENV = "" })))
		end)
	end)
end)

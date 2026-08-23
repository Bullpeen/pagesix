--- Synthetic `anonymous_coward` account spec.
-- Migration [10] creates it; [111] backfills it on databases that recorded [10]
-- as applied while it was silently failing. Both call the same idempotent
-- helper, so running either -- or both, twice -- must leave exactly one row.

local use_test_env = require("lapis.spec").use_test_env

describe("anonymous user migration", function()
	use_test_env()

	local Users = require("models.users")
	local Password = require("src.utils.password")
	local migrations = require("migrations")

	setup(function()
		-- schema_helper deliberately skips [10] (the id-sensitive specs assume
		-- their own first user is id 1), so run it here against the schema.
		require("spec.schema_helper")()
	end)

	it("creates the account, with a password nobody can use", function()
		migrations[10]()

		local anon = Users:anonymous()
		assert.is_truthy(anon)
		assert.same("anonymous_coward", anon.user_name)
		-- Not "" -- that is what the constraint rejected, silently skipping the
		-- account entirely. It must be a real bcrypt digest that never verifies.
		assert.truthy(anon.user_pass:match("^%$2"))
		for _, guess in ipairs({ "", "password", "anonymous", anon.user_pass }) do
			assert.is_false(Password.verify(guess, anon.user_pass))
		end
	end)

	it("is idempotent across [10] and the [111] backfill", function()
		migrations[10]()
		migrations[111]()
		migrations[111]()

		local rows = Users:select("WHERE user_name = ?", Users.ANONYMOUS)
		assert.same(1, #rows)
	end)
end)

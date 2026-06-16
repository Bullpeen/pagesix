--- Subreddit name-search spec
-- Exercises Forum:search against an in-memory database. Substring matching and
-- the blank-query contract hold everywhere; the typo-tolerance example needs
-- sqlean's fuzzy extension (present in the production Docker image / `docker` CI
-- job) so it marks itself pending where the bundle isn't installed.

local use_test_env = require("lapis.spec").use_test_env
local Forum = require("src.models.forum")

local function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function names_of(rows)
	local set = {}
	for _, r in ipairs(rows) do
		set[r.name] = true
	end
	return set
end

describe("Forum:search", function()
	use_test_env()

	-- Mirrors Forum:search's own default-path resolution.
	local have_fuzzy =
		file_exists(os.getenv("SQLITE_EXTENSIONS") or "/usr/local/lib/sqlite/sqlean.so")

	setup(function()
		require("spec.schema_helper")()
		-- forum.creator_id is a FK into users, so a creator must exist first.
		local creator = require("models.users"):create({
			user_name = "search_owner",
			user_pass = "password",
			user_email = "owner@example.com",
		})
		for _, name in ipairs({ "programming", "python", "gardening" }) do
			Forum:create({ name = name, creator_id = creator.id })
		end
	end)

	it("returns nothing for a blank query", function()
		assert.same({}, Forum:search(""))
		assert.same({}, Forum:search("   "))
	end)

	it("finds a sub by case-insensitive substring", function()
		assert.truthy(names_of(Forum:search("PROGRAM"))["programming"])
		assert.is_nil(names_of(Forum:search("PROGRAM"))["gardening"])
	end)

	it("tolerates typos when the fuzzy extension is available", function()
		if not have_fuzzy then
			pending("sqlean fuzzy extension not installed in this environment")
			return
		end
		-- "programing" (a dropped m) is not a substring of "programming", so only
		-- Jaro-Winkler ranking can surface it.
		assert.truthy(names_of(Forum:search("programing"))["programming"])
	end)
end)

--- Post search spec
-- Exercises Posts:search. The FTS5 path (exact/token matching) holds
-- everywhere; the typo-tolerant fallback needs sqlean's fuzzy extension
-- (present in the production Docker image / `docker` CI job) so it marks itself
-- pending where the bundle isn't installed.

local use_test_env = require("lapis.spec").use_test_env
local Posts = require("src.models.posts")
local Forum = require("src.models.forum")
local Users = require("models.users")

local function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function titles_of(rows)
	local set = {}
	for _, r in ipairs(rows) do
		set[r.title] = true
	end
	return set
end

describe("Posts:search", function()
	use_test_env()

	-- Mirrors sqlite_ext's own default-path resolution.
	local have_fuzzy =
		file_exists(os.getenv("SQLITE_EXTENSIONS") or "/usr/local/lib/sqlite/sqlean.so")

	setup(function()
		require("spec.schema_helper")()
		local author = Users:create({
			user_name = "search_author",
			user_pass = "password",
			user_email = "search_author@example.com",
		})
		local sub = Forum:create({ name = "searchsub", creator_id = author.id })
		for _, title in ipairs({ "Functional programming in Lua", "Gardening tips" }) do
			Posts:create({ user_id = author.id, sub_id = sub.id, title = title })
		end
	end)

	it("returns nothing for a blank query", function()
		assert.same({}, Posts:search(""))
		assert.same({}, Posts:search(nil))
	end)

	it("finds a post via the FTS5 index", function()
		assert.truthy(titles_of(Posts:search("programming"))["Functional programming in Lua"])
		assert.is_nil(titles_of(Posts:search("programming"))["Gardening tips"])
	end)

	it("falls back to fuzzy matching on a typo when the extension is available", function()
		if not have_fuzzy then
			pending("sqlean fuzzy extension not installed in this environment")
			return
		end
		-- "programing" (a dropped m) is not an FTS5 term match, so only the
		-- word-level Jaro-Winkler fallback over titles can surface the post.
		assert.truthy(titles_of(Posts:search("programing"))["Functional programming in Lua"])
		-- A genuine non-match still returns nothing (no wild fuzzy matches).
		assert.same({}, Posts:search("xyzzyqwerty"))
	end)
end)

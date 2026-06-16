--- SQLite loadable-extension spec
-- Verifies src/utils/sqlite_ext loads the sqlean bundle into Lapis's live
-- connection and that its SQL functions become callable. The bundle ships in
-- the production Docker image (the `docker` CI job), so the function-level
-- assertions run there; the generic-Lua `test` job has no bundle installed, so
-- those examples mark themselves pending and only the safety behaviour is
-- asserted.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")
local sqlite_ext = require("src.utils.sqlite_ext")

-- The first extension the module would load, mirroring its own resolution:
-- SQLITE_EXTENSIONS (colon-separated) overrides the default bundle path.
local function configured_path()
	local raw = os.getenv("SQLITE_EXTENSIONS")
	if raw == nil then
		return "/usr/local/lib/sqlite/sqlean.so"
	end
	return raw:match("[^:]+") -- nil when set-but-empty (loading disabled)
end

local function file_exists(path)
	if not path then
		return false
	end
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

describe("sqlite loadable extensions", function()
	use_test_env()

	local have_bundle = file_exists(configured_path())

	it("never raises and returns a boolean", function()
		assert.is_boolean(sqlite_ext.load({ force = true }))
	end)

	it("keeps normal queries working after a load attempt", function()
		sqlite_ext.load({ force = true })
		assert.are.equal(1, tonumber(db.query("SELECT 1 AS one")[1].one))
	end)

	it("exposes sqlean SQL functions once the bundle is loaded", function()
		if not have_bundle then
			pending("sqlean bundle not installed in this environment")
			return
		end

		assert.is_true(sqlite_ext.load({ force = true }))

		local rx = db.query("SELECT regexp_like('abc123', '[0-9]+') AS v")[1].v
		assert.are.equal(1, tonumber(rx))

		local dl = db.query("SELECT dlevenshtein('cat', 'hat') AS v")[1].v
		assert.are.equal(1, tonumber(dl))
	end)
end)

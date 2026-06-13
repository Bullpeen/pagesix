-- Pure-Lua spec for the read_json util (needs cjson; no lapis/DB). Runs in the
-- native fast loop -- see README "Testing".
local read_json = require("src.utils.read_json")

describe("read_json", function()
	local function write_tmp(content)
		local path = os.tmpname()
		local f = assert(io.open(path, "wb"))
		f:write(content)
		f:close()
		return path
	end

	it("decodes a JSON file into a table", function()
		local path = write_tmp('[{"name":"a"},{"name":"b"}]')
		local data = read_json(path)
		os.remove(path)
		assert.same(2, #data)
		assert.same("a", data[1].name)
		assert.same("b", data[2].name)
	end)

	it("returns nil for a missing file", function()
		assert.is_nil(read_json("/no/such/path/initial_subs.json"))
	end)

	it("raises on malformed JSON (fails loudly rather than seeding nothing)", function()
		local path = write_tmp("{ not valid json")
		assert.has_error(function() read_json(path) end)
		os.remove(path)
	end)
end)

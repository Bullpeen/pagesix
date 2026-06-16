--- Secure-token helper spec
-- Pure-Lua: asserts utils.token returns hex of the requested width and that
-- tokens don't repeat. luaossl ships in both CI environments, so the CSPRNG
-- path is the one under test here.

local token = require("src.utils.token")

describe("utils.token", function()
	it("returns a hex string of the requested byte width", function()
		assert.are.equal(64, #token.hex()) -- default: 32 bytes -> 64 hex chars
		assert.are.equal(32, #token.hex(16))
		assert.are.equal(8, #token.hex(4))
	end)

	it("contains only hex characters", function()
		assert.truthy(token.hex(16):match("^%x+$"))
	end)

	it("produces distinct tokens", function()
		assert.are_not.equal(token.hex(), token.hex())
	end)
end)

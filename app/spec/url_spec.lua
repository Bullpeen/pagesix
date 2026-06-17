--- URL helper spec
-- Pure-Lua: exercises utils.url.domain (socket.url-backed) against the edge
-- cases the old `^%w+://([^/]+)` pattern got wrong -- ports, "www.", case, and
-- scheme-less / empty input.

local Url = require("src.utils.url")

describe("utils.url.domain", function()
	it("extracts the host of a normal URL", function()
		assert.are.equal("example.com", Url.domain("https://example.com/foo/bar"))
	end)

	it("strips a leading www. and lowercases", function()
		assert.are.equal("example.com", Url.domain("https://www.EXAMPLE.com/x"))
	end)

	it("drops the port", function()
		assert.are.equal("example.com", Url.domain("http://example.com:8080/x?y=1"))
	end)

	it("keeps non-www subdomains", function()
		assert.are.equal("docs.example.com", Url.domain("https://docs.example.com/"))
	end)

	it("returns empty string for blank, nil, or host-less input", function()
		assert.are.equal("", Url.domain(nil))
		assert.are.equal("", Url.domain(""))
		assert.are.equal("", Url.domain("not a url"))
	end)
end)

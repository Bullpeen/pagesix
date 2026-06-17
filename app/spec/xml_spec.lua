--- XML escape spec (utils.xml, shared by rss.lua and sitemap.lua)

local Xml = require("src.utils.xml")

describe("utils.xml.escape", function()
	it("escapes the five XML predefined entities", function()
		assert.are.equal("&amp;&lt;&gt;&quot;&apos;", Xml.escape("&<>\"'"))
	end)

	it("leaves ordinary text untouched", function()
		assert.are.equal("hello world", Xml.escape("hello world"))
	end)

	it("coerces nil and numbers to a string", function()
		assert.are.equal("", Xml.escape(nil))
		assert.are.equal("42", Xml.escape(42))
	end)
end)

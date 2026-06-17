--- Email validation spec (utils.email, lpeg_patterns-backed)

local Email = require("src.utils.email")

describe("utils.email.is_valid", function()
	it("accepts ordinary addresses", function()
		assert.is_true(Email.is_valid("a@b.com"))
		assert.is_true(Email.is_valid("foo.bar+tag@sub.example.co.uk"))
	end)

	it("accepts single-label domains (e.g. the system @localhost users)", function()
		assert.is_true(Email.is_valid("rss_bot@localhost"))
		assert.is_true(Email.is_valid("anonymous@localhost"))
	end)

	it("rejects malformed addresses", function()
		assert.is_false(Email.is_valid("nope"))
		assert.is_false(Email.is_valid("@b.com"))
		assert.is_false(Email.is_valid("a@"))
		assert.is_false(Email.is_valid("a b@c.com"))
	end)

	it("rejects empty / non-string input", function()
		assert.is_false(Email.is_valid(""))
		assert.is_false(Email.is_valid(nil))
		assert.is_false(Email.is_valid(123))
	end)
end)

-- Pure-Lua specs for the spam util's tokenizer and its fail-open contract.
-- lapis-bayes is NOT installed in the fast-loop env, which is exactly what lets
-- us assert that is_spam fails OPEN when the classifier is unavailable.
local Spam = require("src.utils.spam")

describe("spam.tokenize", function()
	it("lowercases and keeps alphabetic runs of >= 2 chars", function()
		assert.same(
			{ "hello", "world", "lua", "lang" },
			Spam.tokenize("Hello, WORLD! Lua-lang 4 u")
		)
	end)

	it("returns an empty list for nil / empty / wordless input", function()
		assert.same({}, Spam.tokenize(nil))
		assert.same({}, Spam.tokenize(""))
		assert.same({}, Spam.tokenize("12 3 !!! -"))
	end)
end)

describe("spam.is_spam (fail-open)", function()
	it("returns false on empty text without touching the classifier", function()
		assert.is_false(Spam.is_spam(""))
		assert.is_false(Spam.is_spam(nil))
	end)

	it("fails open (false) when lapis-bayes is unavailable", function()
		-- No bayes rock here, so classify_text can't be required -> pcall fails
		-- -> never blocks. (The positive path is covered by the Docker suite.)
		assert.is_false(Spam.is_spam("free money click here to win a prize now"))
	end)
end)

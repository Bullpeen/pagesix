--- Naive Bayesian spam filtering, wrapping the (previously unused) lapis-bayes
--- dependency. lapis-bayes defaults to a Postgres-only tokenizer, so we inject
--- a pure-Lua one; its migrations are Postgres-shaped too, so the tables are
--- created by our migration `[12]` instead.
-- @module utils.spam

local M = {}

-- Exactly two categories (the bayes classifier compares a pair).
local CATEGORIES = { "spam", "ham" }

-- Only block when the classifier is quite sure (probability of the winning
-- category). Kept high so a small corpus can't easily block legitimate posts.
local SPAM_THRESHOLD = 0.95

-- Short text carries too little signal to classify reliably (a 3-word link
-- title shouldn't be judged), so below this many tokens we never flag.
local MIN_TOKENS = 5

--- Tokenize text into lowercase alphabetic words (>= 2 chars). Pure + exposed
--- so it can be unit-tested without a DB / lapis-bayes.
-- @tparam string text
-- @treturn table list of word tokens
function M.tokenize(text)
	local words = {}
	for w in tostring(text or ""):lower():gmatch("%a%a+") do
		words[#words + 1] = w
	end
	return words
end

-- Pass our tokenizer to lapis-bayes (bypasses its Postgres `to_tsvector`).
local OPTS = {
	tokenize_text = function(text)
		return M.tokenize(text)
	end,
}

-- A tiny built-in corpus. Enough to catch obvious link/scam spam; a real
-- deployment would keep training from moderator actions.
local CORPUS = {
	spam = {
		"buy cheap viagra and cialis online no prescription needed",
		"free money make cash fast working from home click here now",
		"congratulations you won a prize claim your free gift card today",
		"hot singles in your area want to meet you click this link",
		"earn bitcoin crypto investment double your money guaranteed returns",
		"limited time offer discount pills cheap meds order now save big",
		"work from home and earn thousands per week no experience click",
		"claim your free iphone winner selected click the link to redeem",
	},
	ham = {
		"i really enjoyed this article about lua programming and databases",
		"the weather today is nice lets discuss the football game results",
		"can someone explain how recursive common table expressions work",
		"i think the new season of the show was better than the last one",
		"here is a recipe for sourdough bread that my family really likes",
		"what books would you recommend for learning systems programming",
		"the hiking trail was beautiful this weekend with great views",
		"does anyone have tips for debugging memory leaks in c programs",
	},
}

--- Train the built-in corpus. Idempotent enough for a one-shot migration; safe
--- to call in tests after the bayes tables exist.
function M.train_defaults()
	local bayes = require("lapis.bayes")
	for _, category in ipairs(CATEGORIES) do
		for _, text in ipairs(CORPUS[category]) do
			bayes.train_text(category, text, OPTS)
		end
	end
end

--- Classify text; true only if it's spam above the confidence threshold.
--- Fails OPEN (false) on any error or an untrained classifier, so the filter
--- can never block content when misconfigured/unavailable.
-- @tparam string text
-- @treturn boolean
function M.is_spam(text)
	if not text or text == "" then
		return false
	end
	if #M.tokenize(text) < MIN_TOKENS then
		return false
	end
	local ok, category, prob = pcall(function()
		return require("lapis.bayes").classify_text(CATEGORIES, text, OPTS)
	end)
	if not ok or not category then
		return false
	end
	return category == "spam" and (tonumber(prob) or 0) >= SPAM_THRESHOLD
end

return M

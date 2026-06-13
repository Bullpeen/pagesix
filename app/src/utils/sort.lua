--- Sort utils
-- @module utils.sort

local os = require("os")

local Sort = {}
Sort.__index = Sort

-- Vote aggregates may be missing on some rows; treat absent as 0 so the
-- comparators never error on nil arithmetic/comparison.
local function num(x)
	return tonumber(x) or 0
end

local function best(a, b)
	-- sort descending by Upvotes
	return num(a.upvotes) > num(b.upvotes)
end

-- Reddit's controversy score: weight total vote volume by how evenly the votes
-- are split. A post is only controversial if it drew votes on BOTH sides, so a
-- one-sided (or unvoted) post scores 0.
--
--   score = (up + down) ^ (min(up, down) / max(up, down))
--
-- The exponent (the "balance") is 1.0 for a perfect 50/50 split and approaches
-- 0 as the split becomes lopsided, so a hotly-contested 500/500 post outranks a
-- quiet 1/1 even though both are perfectly balanced.
local function controversy_score(x)
	local up, down = num(x.upvotes), num(x.downvotes)
	if up <= 0 or down <= 0 then
		return 0
	end
	local balance = math.min(up, down) / math.max(up, down)
	return (up + down) ^ balance
end

local function controversial(a, b)
	-- sort descending by controversy score
	return controversy_score(a) > controversy_score(b)
end

local function date_to_timestamp(date_str, pattern)
	-- date_str="2004-07-06 20:4:20"
	pattern = pattern or "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"

	if not date_str then
		return 0
	end

	local year, month, day, hour, min, sec = date_str:match(pattern)
	if not year then
		return 0
	end
	local offset = os.time() - os.time(os.date("!*t"))

	local seconds = os.time({
		day = day,
		month = month,
		year = year,
		hour = hour,
		min = min,
		sec = sec,
	}) + offset

	-- print("TIME: " .. s .. " IN SECONDS IS " .. seconds)
	return seconds
end

local function hot(a, b)
	-- log10 of the score and weighs it against 12 hour periods

	-- log( abs( Upvotes - Downvotes ) + ( age_in_seconds / 45000 ))

	local a_hot =
		math.log(math.abs(num(a.upvotes) - num(a.downvotes)) + (date_to_timestamp(a.age) / 45000)) -- 43,200 == 12 hours
	local b_hot =
		math.log(math.abs(num(b.upvotes) - num(b.downvotes)) + (date_to_timestamp(b.age) / 45000))

	-- print("HOT A=" .. a_hot .. ", B=" .. b_hot)
	return a_hot > b_hot
end

-- "rising" = vote velocity: net score per hour since posting, so new posts
-- gaining votes quickly outrank old posts with more total votes.
local function velocity(x)
	local age_seconds = os.time() - date_to_timestamp(x.age)
	local hours = math.max(age_seconds / 3600, 1)
	return (num(x.upvotes) - num(x.downvotes)) / hours
end

local function rising(a, b)
	return velocity(a) > velocity(b)
end

local function top(a, b)
	-- sort descending by Upvotes - Downvotes
	local a_total = num(a.upvotes) - num(a.downvotes)
	local b_total = num(b.upvotes) - num(b.downvotes)
	-- print("TOP A=" .. a_total .. ", B=" .. b_total)
	return a_total > b_total
end

-- Comparators keyed by algo name; anything not listed falls back to `hot`.
local comparators = {
	best = best,
	top = top,
	controversial = controversial,
	rising = rising,
	hot = hot,
}

function Sort:sort(items, algo)
	local cmp = comparators[algo] or hot

	local arr = {}
	for _, n in pairs(items) do
		table.insert(arr, n)
	end
	table.sort(arr, cmp)

	return arr
end

return Sort

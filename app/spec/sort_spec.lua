-- Pure-Lua specs for the sort comparators. Deliberately requires nothing but
-- `src.utils.sort` so it runs without the lapis/openresty stack (the rest of
-- the suite needs a DB + lapis; these don't).
local Sort = require("src.utils.sort")

describe("Sort:sort dispatch", function()
	local rows = {
		{ id = 1, upvotes = 1, downvotes = 0 },
		{ id = 2, upvotes = 9, downvotes = 1 },
		{ id = 3 }, -- missing vote fields -> treated as 0, must not error
	}

	it("orders by 'top' (net score, descending)", function()
		local sorted = Sort:sort(rows, "top")
		assert.same(2, sorted[1].id) -- score 8
		assert.same(1, sorted[2].id) -- score 1
		assert.same(3, sorted[3].id) -- score 0
	end)

	it("orders by 'best' (raw upvotes, descending)", function()
		local sorted = Sort:sort(rows, "best")
		assert.same(2, sorted[1].id) -- 9 upvotes
		assert.same(1, sorted[2].id) -- 1 upvote
		assert.same(3, sorted[3].id) -- 0
	end)

	it("falls back to 'hot' for an unknown algo without erroring", function()
		local sorted = Sort:sort(rows, "nonsense")
		assert.same(3, #sorted) -- all rows returned, order is hot's call
	end)

	it("does not mutate the caller's table", function()
		local input = { { id = 1, upvotes = 3 }, { id = 2, upvotes = 7 } }
		Sort:sort(input, "best")
		assert.same(1, input[1].id) -- original order preserved
		assert.same(2, input[2].id)
	end)
end)

describe("Sort 'controversial' (Reddit formula)", function()
	-- score = (up + down) ^ (min/max); 0 when either side has no votes.
	it("ranks balanced, high-volume posts above balanced low-volume ones", function()
		local rows = {
			{ id = "small", upvotes = 5, downvotes = 5 }, -- 10 ^ 1   = 10
			{ id = "big", upvotes = 500, downvotes = 500 }, -- 1000 ^ 1 = 1000
		}
		local sorted = Sort:sort(rows, "controversial")
		assert.same("big", sorted[1].id)
		assert.same("small", sorted[2].id)
	end)

	it("ranks evenly-split posts above lopsided ones of similar volume", function()
		local rows = {
			{ id = "lopsided", upvotes = 100, downvotes = 2 }, -- 102 ^ 0.02 ~= 1.10
			{ id = "even", upvotes = 5, downvotes = 5 }, -- 10 ^ 1 = 10
		}
		local sorted = Sort:sort(rows, "controversial")
		assert.same("even", sorted[1].id)
		assert.same("lopsided", sorted[2].id)
	end)

	it("scores one-sided or unvoted posts as not controversial (last)", function()
		local rows = {
			{ id = "ups_only", upvotes = 50, downvotes = 0 }, -- 0
			{ id = "downs_only", upvotes = 0, downvotes = 40 }, -- 0
			{ id = "contested", upvotes = 3, downvotes = 3 }, -- 6 ^ 1 = 6
			{ id = "empty" }, -- 0, must not error
		}
		local sorted = Sort:sort(rows, "controversial")
		assert.same("contested", sorted[1].id)
		-- the three zero-score rows trail the contested one
		assert.same(4, #sorted)
	end)
end)

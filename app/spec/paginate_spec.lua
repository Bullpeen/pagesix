-- Pure-Lua specs for the pagination utils. Requires nothing but the utils, so
-- it runs in the native fast loop (no lapis/DB) -- see README "Testing".
local paginate = require("src.utils.paginate")
local paginate_thread = require("src.utils.paginate_thread")

describe("paginate (flat list)", function()
	local items = {}
	for i = 1, 7 do items[i] = i end

	it("slices a page and reports metadata", function()
		local page, info = paginate(items, 2, 3)
		assert.same({ 4, 5, 6 }, page)
		assert.same(2, info.page)
		assert.same(7, info.total)
		assert.is_true(info.has_prev)
		assert.is_true(info.has_next)
	end)

	it("flags the last page (no next)", function()
		local page, info = paginate(items, 3, 3)
		assert.same({ 7 }, page)
		assert.is_true(info.has_prev)
		assert.is_false(info.has_next)
	end)

	it("defaults to page 1 and clamps bad/low page numbers", function()
		local _, info = paginate(items, 0, 3)
		assert.same(1, info.page)
		assert.is_false(info.has_prev)
	end)

	it("returns an empty page past the end without erroring", function()
		local page, info = paginate(items, 99, 3)
		assert.same({}, page)
		assert.is_false(info.has_next)
	end)
end)

describe("paginate_thread (by root comment)", function()
	-- A(0) > A1(1), A2(1) ; B(0) > B1(1) ; C(0)  -- depth-ordered like the CTE
	local rows = {
		{ id = "A", depth = 0 },
		{ id = "A1", depth = 1 },
		{ id = "A2", depth = 1 },
		{ id = "B", depth = 0 },
		{ id = "B1", depth = 1 },
		{ id = "C", depth = 0 },
	}

	local function ids(t)
		local out = {}
		for i, r in ipairs(t) do out[i] = r.id end
		return out
	end

	it("counts roots, not rows, for totals", function()
		local _, info = paginate_thread(rows, 1, 2)
		assert.same(3, info.total) -- A, B, C (not 6 rows)
	end)

	it("keeps each root's whole subtree on its page", function()
		local page, info = paginate_thread(rows, 1, 2)
		assert.same({ "A", "A1", "A2", "B", "B1" }, ids(page))
		assert.is_false(info.has_prev)
		assert.is_true(info.has_next)
	end)

	it("returns the next page of roots with their subtrees", function()
		local page, info = paginate_thread(rows, 2, 2)
		assert.same({ "C" }, ids(page))
		assert.is_true(info.has_prev)
		assert.is_false(info.has_next)
	end)

	it("returns everything on one page when it fits", function()
		local page, info = paginate_thread(rows, 1, 25)
		assert.same(6, #page)
		assert.is_false(info.has_next)
	end)

	it("handles an empty thread", function()
		local page, info = paginate_thread({}, 1, 25)
		assert.same({}, page)
		assert.same(0, info.total)
		assert.is_false(info.has_prev)
		assert.is_false(info.has_next)
	end)

	it("returns an empty page past the last root", function()
		local page, info = paginate_thread(rows, 3, 2)
		assert.same({}, page)
		assert.is_true(info.has_prev)
		assert.is_false(info.has_next)
	end)
end)

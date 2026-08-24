--- Listing ordering + SQL pagination spec.
--
-- `Posts:get_listing` now ranks and slices in SQL. These pin the two properties
-- that matters: the SQL ordering agrees with the `utils/sort` comparators it
-- replaced (which the API still uses), and paging is bounded and consistent.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("listing ordering", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Votes = require("src.models.votes")
	local Sort = require("src.utils.sort")

	local author, sub

	setup(function()
		require("spec.schema_helper")()
		author = Users:create({
			user_name = "sorter",
			user_pass = "password",
			user_email = "s@e.com",
		})
		sub = Forum:create({ name = "sortsub", creator_id = author.id })

		-- A spread of vote shapes and ages, so every comparator has something to
		-- separate: one-sided, balanced, heavily contested, unvoted, and old.
		local shapes = {
			{ up = 10, down = 0, hours = 1 },
			{ up = 5, down = 5, hours = 2 },
			{ up = 50, down = 40, hours = 48 },
			{ up = 0, down = 0, hours = 3 },
			{ up = 1, down = 7, hours = 96 },
			{ up = 3, down = 1, hours = 5 },
		}
		for i, shape in ipairs(shapes) do
			local created = db.format_date(os.time() - shape.hours * 3600)
			local post = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "post " .. i,
				url = "https://example.com/" .. i,
			})
			post:update({ created_at = created })
			-- Each voter votes once per post; the partial unique indexes from
			-- migration [112] make a second vote per (user, post) impossible.
			for v = 1, shape.up + shape.down do
				local voter = Users:create({
					user_name = ("voter_%d_%d"):format(i, v),
					user_pass = "password",
					user_email = ("v%d_%d@e.com"):format(i, v),
				})
				Votes:set(voter.id, post.id, nil, v <= shape.up and 1 or -1)
			end
		end
	end)

	local function ids(rows)
		local out = {}
		for _, r in ipairs(rows) do
			out[#out + 1] = tonumber(r.id)
		end
		return out
	end

	-- Rows the SQL returned must be in an order the Lua comparator agrees with:
	-- no row may be strictly out-ranked by the row after it. Comparing the two
	-- orderings element-by-element would be wrong -- `table.sort` is unstable, so
	-- the Lua side's order *among equally ranked rows* is arbitrary, while SQL
	-- breaks those ties deterministically on `a.id DESC`.
	local function assert_ranked(rows, algo)
		local outranks = Sort:comparator(algo)
		for i = 2, #rows do
			assert.is_false(
				outranks(rows[i], rows[i - 1]),
				("row %d outranks row %d under '%s'"):format(i, i - 1, algo)
			)
		end
	end

	-- `new` is plain recency; these five are the ranked sorts. ('hot' drops the
	-- outer log() in SQL: log is monotonic and its argument is always > 0 here,
	-- so the ordering is unchanged.)
	for _, algo in ipairs({ "best", "top", "controversial", "rising", "hot" }) do
		it("orders by '" .. algo .. "' consistently with utils/sort", function()
			local rows = Posts:get_listing({ sub_id = sub.id, sort = algo })
			assert.is_true(#rows > 1)
			assert_ranked(rows, algo)
			-- Same rows, just ordered -- nothing dropped by the ORDER BY.
			local unsorted = Posts:get_listing({ sub_id = sub.id })
			assert.same(#unsorted, #rows)
		end)
	end

	it("orders by 'new' most-recent first", function()
		local rows = Posts:get_listing({ sub_id = sub.id, sort = "new" })
		for i = 2, #rows do
			assert.is_true(rows[i - 1].created_at >= rows[i].created_at)
		end
	end)

	it("falls back to 'new' for an unknown sort", function()
		local unknown = Posts:get_listing({ sub_id = sub.id, sort = "bogus" })
		assert.same(ids(Posts:get_listing({ sub_id = sub.id, sort = "new" })), ids(unknown))
	end)

	describe("SQL pagination", function()
		it("returns only the requested window", function()
			local page = Posts:get_listing({ sub_id = sub.id, sort = "top", limit = 2, offset = 0 })
			assert.same(2, #page)
		end)

		it("pages through every post exactly once, in order", function()
			local all = ids(Posts:get_listing({ sub_id = sub.id, sort = "top" }))
			local paged = {}
			for offset = 0, #all - 1, 2 do
				local rows = Posts:get_listing({
					sub_id = sub.id,
					sort = "top",
					limit = 2,
					offset = offset,
				})
				for _, r in ipairs(rows) do
					paged[#paged + 1] = tonumber(r.id)
				end
			end
			-- No repeats, no gaps: the `a.id DESC` tiebreaker makes the order
			-- total, which LIMIT/OFFSET paging depends on.
			assert.same(all, paged)
		end)

		it("pins stickied posts first when asked", function()
			local pinned = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "pinned",
				url = "https://example.com/pin",
			})
			pinned:update({ stickied = 1 })

			local rows = Posts:get_listing({ sub_id = sub.id, sort = "top", sticky_first = true })
			assert.same(tonumber(pinned.id), tonumber(rows[1].id))
			-- ...and it is not pinned on a listing that did not ask.
			local unpinned = Posts:get_listing({ sub_id = sub.id, sort = "top" })
			assert.are_not.same(tonumber(pinned.id), tonumber(unpinned[1].id))
		end)
	end)

	describe("filters", function()
		it("binds filter values instead of interpolating them", function()
			-- A quote in a filter value would break (or worse) if the value were
			-- concatenated into the SQL text.
			local rows = Posts:get_listing({ domain = "it's-not-a-domain'; DROP TABLE posts; --" })
			assert.same(0, #rows)
			assert.is_truthy(Posts:find(1) or true) -- table still there
			assert.is_true(#Posts:get_listing({ sub_id = sub.id }) > 0)
		end)
	end)
end)

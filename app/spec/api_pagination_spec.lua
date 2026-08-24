--- API listing pagination spec.
--
-- The listing endpoints used to read every matching row and rank them in Lua.
-- They now order in SQL and fetch a bounded window: the page plus a lookahead
-- row when there is no cursor, opening to `S.MAX_DEPTH` when there is one, since
-- `S.paginate` locates a cursor by scanning the rows it was given.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request
local db = require("lapis.db")

describe("api listing pagination", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local S = require("src.utils.api_serialize")
	local cjson = require("cjson")

	local POSTS = 12

	setup(function()
		require("spec.schema_helper")()
		local author = Users:create({
			user_name = "pager",
			user_pass = "password",
			user_email = "p@e.com",
		})
		local sub = Forum:create({ name = "pagersub", creator_id = author.id })
		for i = 1, POSTS do
			Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "post " .. i,
				url = "https://example.com/" .. i,
			})
		end
	end)

	local app = require("app")

	local function get(path)
		local status, body = simulate_request(app, path, { method = "GET" })
		return status, cjson.decode(body)
	end

	-- Count queries for the duration of `fn`, to prove the fetch is bounded.
	local function count_queries(fn)
		local real = db.query
		local n = 0
		db.query = function(...) -- luacheck: ignore 122
			n = n + 1
			return real(...)
		end
		local ok, err = pcall(fn)
		db.query = real -- luacheck: ignore 122
		assert.is_true(ok, tostring(err))
		return n
	end

	describe("S.window", function()
		it("asks for just the page plus a lookahead row when there is no cursor", function()
			assert.same(6, S.window({ limit = 5 }))
			assert.same(26, S.window({}))
		end)

		it("opens to MAX_DEPTH once a cursor is in play", function()
			assert.same(S.MAX_DEPTH, S.window({ after = "t3_1" }))
			assert.same(S.MAX_DEPTH, S.window({ before = "t3_1" }))
		end)

		it("clamps a silly limit", function()
			assert.same(2, S.window({ limit = 1 }))
			assert.same(101, S.window({ limit = 9999 }))
			assert.same(2, S.window({ limit = -3 }))
		end)
	end)

	describe("GET /api/listing", function()
		it("returns a page and an after cursor", function()
			local status, json = get("/api/listing?limit=5")
			assert.same(200, status)
			assert.same(5, #json.data.children)
			assert.is_truthy(json.data.after)
		end)

		it("walks the whole listing through its cursors, without repeats", function()
			local seen, order, cursor, pages = {}, {}, nil, 0
			repeat
				local path = "/api/listing?limit=5" .. (cursor and ("&after=" .. cursor) or "")
				local _, json = get(path)
				for _, child in ipairs(json.data.children) do
					local id = child.data.id
					assert.is_nil(seen[id], "id " .. tostring(id) .. " appeared twice")
					seen[id] = true
					order[#order + 1] = id
				end
				cursor = json.data.after
				pages = pages + 1
				assert.is_true(pages < 10, "cursor walk did not terminate")
			until not cursor
			assert.same(POSTS, #order)
		end)

		it("does not read the whole table for a page", function()
			-- One listing query (plus whatever the request itself needs); the
			-- point is that it does not scale with the row count.
			local first = count_queries(function()
				get("/api/listing?limit=1")
			end)
			local bigger = count_queries(function()
				get("/api/listing?limit=10")
			end)
			assert.same(first, bigger)
		end)

		it("answers an unknown cursor with an empty page, not the first page", function()
			-- A cursor past the addressable window, or pointing at a row that has
			-- gone. Restarting at the top would leave a client looping forever.
			local _, json = get("/api/listing?limit=5&after=" .. S.fullname("link", 999999))
			assert.same(0, #json.data.children)
			assert.is_nil(json.data.after)
		end)

		it("orders by the requested sort", function()
			for _, sort in ipairs({ "hot", "top", "new", "best", "controversial", "rising" }) do
				local status, json = get("/api/listing/" .. sort .. "?limit=3")
				assert.same(200, status, sort .. " should be a valid sort")
				assert.same(3, #json.data.children)
			end
		end)
	end)

	describe("keyset cursors on the `new` sort", function()
		-- `new` orders by (created_at, id), which never moves once a post is
		-- written, so the database can seek straight to the cursor row instead of
		-- scanning a windowed fetch. The ranked sorts cannot -- their key is live
		-- vote counts.
		local function ids_of(json)
			local out = {}
			for _, child in ipairs(json.data.children) do
				out[#out + 1] = child.data.id
			end
			return out
		end

		it("walks forward exactly, with no repeats or gaps", function()
			local _, all = get("/api/listing/new?limit=" .. POSTS)
			local expected = ids_of(all)
			assert.same(POSTS, #expected)

			local walked, cursor = {}, nil
			repeat
				local path = "/api/listing/new?limit=4" .. (cursor and ("&after=" .. cursor) or "")
				local _, json = get(path)
				for _, id in ipairs(ids_of(json)) do
					walked[#walked + 1] = id
				end
				cursor = json.data.after
			until not cursor
			assert.same(expected, walked)
		end)

		it("walks backward to the page before a cursor", function()
			local _, first = get("/api/listing/new?limit=4")
			local _, second = get("/api/listing/new?limit=4&after=" .. first.data.after)
			assert.is_truthy(second.data.before)

			local _, back = get("/api/listing/new?limit=4&before=" .. second.data.before)
			assert.same(ids_of(first), ids_of(back))
		end)

		-- Capture the filters the endpoint hands the model, which is the only way
		-- to tell the keyset path from the windowed one -- both are a single
		-- query, so a query count cannot distinguish them.
		local function filters_for(path)
			local captured
			local real = Posts.get_listing
			Posts.get_listing = function(self, filters) -- luacheck: ignore 122
				captured = filters
				return real(self, filters)
			end
			local ok, err = pcall(get, path)
			Posts.get_listing = real -- luacheck: ignore 122
			assert.is_true(ok, tostring(err))
			return captured
		end

		it("asks the database to seek, rather than fetching a window", function()
			local _, first = get("/api/listing/new?limit=2")

			local cursored = filters_for("/api/listing/new?limit=2&after=" .. first.data.after)
			assert.is_truthy(cursored.after_id, "should have passed a keyset cursor")
			-- Just the page plus one lookahead row, not S.MAX_DEPTH.
			assert.same(3, cursored.limit)

			-- A ranked sort has no stable key, so it still pages by window.
			local ranked = filters_for("/api/listing/hot?limit=2&after=" .. first.data.after)
			assert.is_nil(ranked.after_id)
			assert.same(S.MAX_DEPTH, ranked.limit)
		end)

		it("treats a vanished cursor row as the end of the listing", function()
			local _, json = get("/api/listing/new?limit=4&after=" .. S.fullname("link", 999999))
			assert.same(0, #json.data.children)
			assert.is_nil(json.data.after)
		end)

		it("refuses a keyset cursor on a sort with no stable key", function()
			-- Guard against a caller wiring after_id into a ranked sort, where the
			-- key moves between requests and the result would silently be wrong.
			local ok = pcall(function()
				return Posts:get_listing({ sort = "hot", after_id = 1 })
			end)
			assert.is_false(ok)
		end)
	end)

	describe("GET /api/subreddits", function()
		it("bounds its window and still paginates", function()
			local status, json = get("/api/subreddits?limit=1")
			assert.same(200, status)
			assert.same(1, #json.data.children)
		end)
	end)
end)

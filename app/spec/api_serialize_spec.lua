--- Unit spec for the API serializer (utils/api_serialize): base36 fullnames,
--- cursor pagination, and the Thing/Listing shaping for each kind.

local use_test_env = require("lapis.spec").use_test_env

describe("api_serialize", function()
	use_test_env()

	local S = require("src.utils.api_serialize")
	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Votes = require("src.models.votes")

	describe("base36 / fullnames", function()
		it("round-trips base36", function()
			for _, n in ipairs({ 0, 1, 35, 36, 42, 1000, 123456789 }) do
				assert.same(n, S.from_base36(S.base36(n)))
			end
			assert.same("16", S.base36(42))
		end)

		it("builds and parses fullnames for every kind", function()
			local cases = {
				{ "link", "posts" },
				{ "comment", "comments" },
				{ "account", "users" },
				{ "subreddit", "forum" },
			}
			for _, c in ipairs(cases) do
				local name = S.fullname(c[1], 42)
				local tbl, id = S.parse_fullname(name)
				assert.same(c[2], tbl)
				assert.same(42, id)
			end
		end)

		it("rejects malformed fullnames", function()
			assert.is_nil(S.parse_fullname("garbage"))
			assert.is_nil(S.parse_fullname("t9_5")) -- unknown prefix
			assert.is_nil(S.parse_fullname("t3_!!")) -- bad base36
			assert.is_nil(S.parse_fullname(nil))
			assert.is_nil(S.from_base36("!!"))
			assert.is_nil(S.from_base36(""))
		end)
	end)

	describe("paginate / listing", function()
		local rows = {}
		for i = 1, 150 do
			rows[i] = { id = i }
		end

		it("defaults to 25 and exposes an after cursor", function()
			local page, after, before = S.paginate(rows, {}, "link")
			assert.same(25, #page)
			assert.same(S.fullname("link", 25), after)
			assert.is_nil(before)
		end)

		it("caps the limit at 100", function()
			local page = S.paginate(rows, { limit = 500 }, "link")
			assert.same(100, #page)
		end)

		it("advances past an after cursor and sets before", function()
			local after = S.fullname("link", 25)
			local page, next_after, before = S.paginate(rows, { limit = 5, after = after }, "link")
			assert.same(26, page[1].id)
			assert.same(5, #page)
			assert.same(S.fullname("link", 26), before)
			assert.same(S.fullname("link", 30), next_after)
		end)

		it("returns no after cursor on the last page", function()
			local small = { { id = 1 }, { id = 2 } }
			local _, after = S.paginate(small, { limit = 10 }, "link")
			assert.is_nil(after)
		end)

		it("wraps children in a Listing envelope", function()
			local l = S.listing({ { kind = "t3" }, { kind = "t3" } }, { after = "t3_2" })
			assert.same("Listing", l.kind)
			assert.same(2, l.data.dist)
			assert.same("t3_2", l.data.after)
		end)
	end)

	describe("Thing shaping", function()
		local demo, sub, post

		setup(function()
			require("spec.schema_helper")()
			demo = Users:create({
				user_name = "serdemo",
				user_pass = "password",
				user_email = "s@e.com",
			})
			sub = Forum:create({ name = "sersub", creator_id = demo.id, description = "ser" })
			post = Posts:create({
				user_id = demo.id,
				sub_id = sub.id,
				title = "Ser Post",
				url = "https://ser.example/a",
			})
		end)

		it("shapes a link from an enriched row", function()
			local t = S.link({
				id = post.id,
				title = "T",
				upvotes = 3,
				downvotes = 1,
				author = "serdemo",
				subreddit = "sersub",
				num_comments = 2,
				is_self = 0,
				created_at = "2024-01-01 00:00:00",
			})
			assert.same("t3", t.kind)
			assert.same(2, t.data.score)
			assert.same(3, t.data.ups)
			assert.same(2, t.data.num_comments)
			assert.is_false(t.data.is_self)
		end)

		it("shapes a link from a bare row (vote/author/sub fallback)", function()
			Votes:set(demo.id, post.id, nil, 1)
			local t = S.link(Posts:find(post.id))
			assert.same("t3", t.kind)
			assert.same("serdemo", t.data.author)
			assert.same("sersub", t.data.subreddit)
			assert.same(1, t.data.ups)
		end)

		it("shapes a comment, blanking a deleted one", function()
			local live = S.comment({
				id = 1,
				post_id = post.id,
				body = "hi",
				author = "serdemo",
				subreddit = "sersub",
				upvotes = 2,
				downvotes = 0,
				deleted = 0,
			})
			assert.same("t1", live.kind)
			assert.same("hi", live.data.body)
			assert.same(2, live.data.score)

			local dead = S.comment({
				id = 2,
				post_id = post.id,
				body = "secret",
				author = "serdemo",
				subreddit = "sersub",
				deleted = 1,
			})
			assert.same("[deleted]", dead.data.body)
			assert.same("[deleted]", dead.data.author)
		end)

		it("shapes an account", function()
			local t = S.account(Users:find(demo.id))
			assert.same("t2", t.kind)
			assert.same("serdemo", t.data.name)
			assert.same(S.fullname("account", demo.id), t.data.fullname)
			assert.is_number(t.data.total_karma)
		end)

		it("shapes a subreddit, and one without an id", function()
			local t = S.subreddit(Forum:find(sub.id))
			assert.same("t5", t.kind)
			assert.same("sersub", t.data.display_name)
			assert.same("r/sersub", t.data.display_name_prefixed)
			assert.is_number(t.data.subscribers)

			-- A projection row without `id` (e.g. Forum:search) degrades gracefully.
			local bare = S.subreddit({ name = "x", description = "d", subscribers = 0 })
			assert.same("x", bare.data.display_name)
			assert.is_nil(bare.data.id)
		end)

		it("mints a stable public_id and re-reads it", function()
			local fresh = Posts:create({
				user_id = demo.id,
				sub_id = sub.id,
				title = "uuid post",
				url = "https://u.example",
			})
			-- A row without public_id (a listing projection): first call mints,
			-- second re-reads the stored value -- both must agree.
			local u1 = S.ensure_public_id("posts", { id = fresh.id })
			local u2 = S.ensure_public_id("posts", { id = fresh.id })
			assert.same(36, #u1)
			assert.same(u1, u2)
			assert.same(u1, Posts:find(fresh.id).public_id)
		end)
	end)
end)

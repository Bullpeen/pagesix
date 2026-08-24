--- Serializer public_id spec.
--
-- `api_serialize.ensure_public_id` re-reads the column when a row arrives
-- without it, so that a projection which simply did not SELECT it is not
-- mistaken for "unset" and clobbered with a fresh uuid. That guard is right,
-- but it meant one extra SELECT per serialized row: the listing projections all
-- omitted `public_id`, so a 25-row Listing cost 25 extra queries.
--
-- These count the queries a serialize actually issues.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("api serializer public_id", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local S = require("src.utils.api_serialize")

	local author, sub

	setup(function()
		require("spec.schema_helper")()
		author = Users:create({
			user_name = "apiser",
			user_pass = "password",
			user_email = "a@e.com",
		})
		sub = Forum:create({ name = "apisub", creator_id = author.id })
		for i = 1, 5 do
			local post = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "post " .. i,
				url = "https://example.com/" .. i,
			})
			Comments:create({ post_id = post.id, user_id = author.id, body = "c" .. i })
		end
	end)

	-- Count queries by wrapping db.query for the duration of `fn`.
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

	it("serializes a listing without a query per row", function()
		local rows = Posts:get_listing({ sub_id = sub.id })
		assert.same(5, #rows)
		local queries = count_queries(function()
			for _, row in ipairs(rows) do
				S.link(row)
			end
		end)
		assert.same(0, queries)
	end)

	it("serializes a comment thread without a query per row", function()
		local post = Posts:get_listing({ sub_id = sub.id })[1]
		local thread = Comments:thread(post.id)
		assert.is_true(#thread > 0)
		local queries = count_queries(function()
			for _, row in ipairs(thread) do
				S.comment(row)
			end
		end)
		assert.same(0, queries)
	end)

	it("still exposes a stable uuid, equal to the stored public_id", function()
		local row = Posts:get_listing({ sub_id = sub.id })[1]
		local thing = S.link(row)
		assert.is_truthy(thing.data.uuid)
		local stored = db.select("public_id FROM posts WHERE id = ?", tonumber(row.id))
		assert.same(stored[1].public_id, thing.data.uuid)
		-- Serializing again returns the same id rather than minting a new one.
		assert.same(thing.data.uuid, S.link(Posts:get_listing({ sub_id = sub.id })[1]).data.uuid)
	end)

	it("still mints an id for a row that genuinely has none", function()
		-- The re-read/mint path stays in place for rows created before the
		-- backfill, or fetched through a projection that omits the column.
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "no id yet",
			url = "https://example.com/mint",
		})
		db.update("posts", { public_id = db.NULL }, { id = post.id })

		local minted = S.ensure_public_id("posts", { id = post.id })
		assert.is_truthy(minted)
		local stored = db.select("public_id FROM posts WHERE id = ?", tonumber(post.id))
		assert.same(minted, stored[1].public_id)
	end)
end)

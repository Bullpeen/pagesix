--- Voting spec
-- Verifies Votes:cast (create / toggle-off / switch) and that votes are
-- reflected in a post's score via Posts:get_listing.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("voting", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")

	setup(function()
		require("spec.schema_helper")()
	end)

	local function make_post(name)
		local u = Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@e.com",
		})
		local f = Forum:create({ name = name .. "_sub", creator_id = u.id })
		local p =
			Posts:create({ user_id = u.id, sub_id = f.id, title = "t", url = "https://e.example" })
		return u, p
	end

	local function post_vote(user_id, post_id)
		return Votes:find({ user_id = user_id, post_id = post_id, comment_id = db.NULL })
	end

	it("creates, toggles off, and switches a post vote", function()
		local u, p = make_post("voter_a")

		Votes:cast(u.id, p.id, nil, 1) -- upvote
		assert.same(1, tonumber(post_vote(u.id, p.id).upvote))

		Votes:cast(u.id, p.id, nil, 1) -- same direction -> undo
		assert.is_nil(post_vote(u.id, p.id))

		Votes:cast(u.id, p.id, nil, 0) -- downvote
		Votes:cast(u.id, p.id, nil, 1) -- switch to upvote
		assert.same(1, tonumber(post_vote(u.id, p.id).upvote))
		-- still exactly one vote row for this (user, post)
		assert.same(
			1,
			#Votes:select("where user_id = ? and post_id = ? and comment_id is null", u.id, p.id)
		)
	end)

	it("reflects votes in the post score via get_listing", function()
		local u1, p = make_post("voter_b")
		local u2 = Users:create({
			user_name = "voter_b2",
			user_pass = "password",
			user_email = "b2@e.com",
		})

		Votes:cast(u1.id, p.id, nil, 1) -- up
		Votes:cast(u2.id, p.id, nil, 0) -- down

		local row
		for _, r in ipairs(Posts:get_listing(p.sub_id)) do
			if r.id == p.id then
				row = r
			end
		end

		assert.is_not_nil(row)
		assert.same(1, tonumber(row.upvotes))
		assert.same(1, tonumber(row.downvotes))
	end)

	it("casts comment votes and aggregates them in Comments:listing", function()
		local u, p = make_post("cvoter")
		local c = Comments:create({ post_id = p.id, user_id = u.id, body = "hi" })
		local u2 =
			Users:create({ user_name = "cvoter2", user_pass = "password", user_email = "c2@e.com" })

		Votes:cast(u.id, p.id, c.id, 1) -- upvote the comment
		Votes:cast(u2.id, p.id, c.id, 0) -- downvote the comment

		-- comment vote rows carry both post_id and comment_id
		local v = Votes:find({ user_id = u.id, post_id = p.id, comment_id = c.id })
		assert.same(1, tonumber(v.upvote))

		local row
		for _, r in ipairs(Comments:thread(p.id)) do
			if r.id == c.id then
				row = r
			end
		end
		assert.is_not_nil(row)
		assert.same(1, tonumber(row.upvotes))
		assert.same(1, tonumber(row.downvotes))
		assert.same(0, row.score)
		assert.same("cvoter", row.author)
	end)

	describe("one vote per user per target", function()
		it("refuses a second post vote row at the database level", function()
			-- The table's UNIQUE(user_id, post_id, comment_id) does NOT cover this:
			-- comment_id is NULL and SQLite treats NULLs as distinct, so before
			-- migration [112] both inserts succeeded and the score double-counted.
			local u, p = make_post("dupe_post")
			local now = db.format_date()
			local function raw_insert()
				return pcall(
					db.query,
					[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
						VALUES (?, ?, NULL, 1, ?, ?)]],
					u.id,
					p.id,
					now,
					now
				)
			end
			assert.is_true((raw_insert()))
			assert.is_false((raw_insert()))
			assert.same(1, #Votes:select("where user_id = ? and post_id = ?", u.id, p.id))
		end)

		it("refuses a second comment vote row at the database level", function()
			local u, p = make_post("dupe_comment")
			local c = Comments:create({ post_id = p.id, user_id = u.id, body = "b" })
			local now = db.format_date()
			local function raw_insert()
				return pcall(
					db.query,
					[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
						VALUES (?, ?, ?, 1, ?, ?)]],
					u.id,
					p.id,
					c.id,
					now,
					now
				)
			end
			assert.is_true((raw_insert()))
			assert.is_false((raw_insert()))
			assert.same(1, #Votes:select("where user_id = ? and comment_id = ?", u.id, c.id))
		end)

		it("re-votes through the upsert instead of inserting a second row", function()
			local u, p = make_post("upsert_post")
			Votes:set(u.id, p.id, nil, 1)
			Votes:set(u.id, p.id, nil, -1) -- switch direction
			Votes:set(u.id, p.id, nil, -1) -- idempotent repeat

			local rows = Votes:select("where user_id = ? and post_id = ?", u.id, p.id)
			assert.same(1, #rows)
			assert.same(0, tonumber(rows[1].upvote))
			assert.same(-1, Votes:post_score(p.id))
		end)
	end)
end)

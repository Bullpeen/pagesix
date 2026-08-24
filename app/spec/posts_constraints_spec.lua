--- CHECK constraints on posts/comments (migration [116]).
--
-- These two are the awkward tables: `posts` is referenced by six others and by
-- itself, carries the FTS5 sync triggers, and both feed the `v_daily_activity`
-- view. So this covers the rebuild as much as the constraints -- re-running the
-- migration against real rows and checking that nothing came unstuck.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("posts/comments constraints", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local migrations = require("migrations")

	local author, sub, post, comment

	setup(function()
		require("spec.schema_helper")()
		author = Users:create({
			user_name = "flagger",
			user_pass = "password",
			user_email = "f@e.com",
		})
		sub = Forum:create({ name = "flagsub", creator_id = author.id })
		post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "findable zebra",
			body = "a searchable body",
			url = "https://e.example",
		})
		comment = Comments:create({ post_id = post.id, user_id = author.id, body = "hello" })
		Votes:set(author.id, post.id, nil, 1)
	end)

	local function insert_fails(sql, ...)
		return not (pcall(db.query, sql, ...))
	end

	it("rejects a non-boolean post flag", function()
		local now = db.format_date()
		assert.is_true(
			insert_fails(
				[[INSERT INTO posts (user_id, sub_id, title, created_at, updated_at, deleted)
				VALUES (?, ?, 'bad', ?, ?, 7)]],
				author.id,
				sub.id,
				now,
				now
			)
		)
	end)

	it("rejects a non-boolean comment flag", function()
		local now = db.format_date()
		assert.is_true(
			insert_fails(
				[[INSERT INTO comments (post_id, user_id, body, created_at, updated_at, approved)
				VALUES (?, ?, 'bad', ?, ?, 5)]],
				post.id,
				author.id,
				now,
				now
			)
		)
	end)

	it("still accepts the flags the app writes", function()
		local p = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "ok",
			url = "https://e.example/ok",
		})
		p:update({ stickied = 1, comments_locked = 1, is_question = 1 })
		assert.same(1, tonumber(Posts:find(p.id).stickied))
		local c = Comments:create({ post_id = p.id, user_id = author.id, body = "c" })
		c:update({ edited = 1, deleted = 1 })
		assert.same(1, tonumber(Comments:find(c.id).deleted))
	end)

	describe("the rebuild", function()
		it("keeps child foreign keys pointing at the rebuilt table", function()
			-- The failure this guards against: renaming the *original* out of the
			-- way (as the leaf-table rebuild does) makes SQLite rewrite child
			-- REFERENCES clauses to follow it, so `comments` would end up naming
			-- `posts_old`. Migration [116] builds under a temp name instead.
			local targets = {}
			for _, fk in ipairs(db.query("PRAGMA foreign_key_list(comments)") or {}) do
				targets[fk.table] = true
			end
			assert.is_true(targets["posts"] == true, "comments should still reference posts")
			for name in pairs(targets) do
				assert.are_not.same("posts_rebuild", name)
				assert.are_not.same("posts_old", name)
			end
		end)

		it("preserves rows, the FTS index and the view when re-run", function()
			local posts_before = tonumber(db.select("count(*) AS n FROM posts")[1].n)
			local comments_before = tonumber(db.select("count(*) AS n FROM comments")[1].n)
			assert.is_true(posts_before > 0 and comments_before > 0)

			migrations[116]()

			assert.same(posts_before, tonumber(db.select("count(*) AS n FROM posts")[1].n))
			assert.same(comments_before, tonumber(db.select("count(*) AS n FROM comments")[1].n))
			assert.same("findable zebra", Posts:find(post.id).title)
			assert.same("hello", Comments:find(comment.id).body)

			-- Full-text search still finds the row: the FTS index was left alone
			-- and its sync triggers were reattached.
			local hits = Posts:search("zebra")
			local found = false
			for _, row in ipairs(hits) do
				if tonumber(row.id) == tonumber(post.id) then
					found = true
				end
			end
			assert.is_true(found, "FTS should still match the seeded post")

			-- The view was dropped and recreated around the swap.
			assert.is_true(#db.select("day FROM v_daily_activity") >= 1)

			-- And the vote still resolves to its post.
			assert.same(1, Votes:post_score(post.id))
		end)

		it("keeps the FTS triggers live for new writes after a rebuild", function()
			local fresh = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "postrebuild quokka",
				url = "https://e.example/q",
			})
			local found = false
			for _, row in ipairs(Posts:search("quokka")) do
				if tonumber(row.id) == tonumber(fresh.id) then
					found = true
				end
			end
			assert.is_true(found, "the reattached AFTER INSERT trigger should have indexed it")
		end)

		it("leaves the expected indexes in place", function()
			local names = {}
			for _, r in ipairs(db.select("name FROM sqlite_master WHERE type = 'index'")) do
				names[r.name] = true
			end
			for _, expected in ipairs({
				"posts_sub_id_idx",
				"posts_user_id_idx",
				"posts_created_at_idx",
				"posts_deleted_idx",
				"posts_sub_id_created_at_idx",
				"posts_sub_id_stickied_idx",
				"posts_external_guid_idx",
				"posts_sub_id_approved_idx",
				"posts_public_id_idx",
				"comments_post_id_idx",
				"comments_parent_comment_id_idx",
				"comments_user_id_idx",
				"comments_post_id_parent_comment_id_idx",
				"comments_post_id_approved_idx",
				"comments_public_id_idx",
			}) do
				assert.is_true(names[expected] == true, expected .. " is missing")
			end
		end)

		it("leaves no orphaned rows", function()
			local orphans = db.query("PRAGMA foreign_key_check")
			assert.same(0, orphans and #orphans or 0)
		end)
	end)
end)

--- CHECK constraint spec (migration [114]).
--
-- STRICT tables guarantee column *types*; these guarantee the *values* for the
-- columns whose domain was previously only enforced in Lua. `votes.upvote` is
-- the one that mattered most: it is read as
-- `CASE WHEN upvote = 1 THEN 1 ELSE -1 END`, so any stray value silently
-- counted as a downvote.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("CHECK constraints", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local migrations = require("migrations")

	local author, sub, post

	setup(function()
		require("spec.schema_helper")()
		author = Users:create({
			user_name = "checker",
			user_pass = "password",
			user_email = "c@e.com",
		})
		sub = Forum:create({ name = "checksub", creator_id = author.id })
		post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "t",
			url = "https://e.example",
		})
	end)

	local function insert_fails(sql, ...)
		local ok = pcall(db.query, sql, ...)
		return not ok
	end

	it("rejects a vote direction outside 0/1", function()
		local now = db.format_date()
		assert.is_true(
			insert_fails(
				[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
				VALUES (?, ?, NULL, 7, ?, ?)]],
				author.id,
				post.id,
				now,
				now
			)
		)
	end)

	it("rejects an unknown forum role", function()
		local now = db.format_date()
		assert.is_true(
			insert_fails(
				[[INSERT INTO roles (subreddit_id, user_id, role, created_at, updated_at)
				VALUES (?, ?, 'wizard', ?, ?)]],
				sub.id,
				author.id,
				now,
				now
			)
		)
	end)

	it("rejects an unknown site role", function()
		local now = db.format_date()
		assert.is_true(insert_fails(
			[[INSERT INTO site_roles (user_id, role, created_at, updated_at)
				VALUES (?, 'superuser', ?, ?)]],
			author.id,
			now,
			now
		))
	end)

	it("rejects an unknown notification kind", function()
		local now = db.format_date()
		assert.is_true(
			insert_fails(
				[[INSERT INTO notifications (user_id, kind, created_at, updated_at)
				VALUES (?, 'carrier_pigeon', ?, ?)]],
				author.id,
				now,
				now
			)
		)
	end)

	it("still accepts every value the app actually writes", function()
		local voter = Users:create({
			user_name = "checkvoter",
			user_pass = "password",
			user_email = "cv@e.com",
		})
		assert.is_truthy(Votes:set(voter.id, post.id, nil, 1))
		assert.is_truthy(Votes:set(voter.id, post.id, nil, -1))

		local Roles = require("src.models.roles")
		for _, role in ipairs({ "owner", "moderator", "member" }) do
			local u = Users:create({
				user_name = "role_" .. role,
				user_pass = "password",
				user_email = role .. "@e.com",
			})
			assert.is_truthy(Roles:assign(sub.id, u.id, role))
		end

		-- notify/notify_mention return nothing, so assert on the stored rows.
		local Notifications = require("models.notifications")
		local comment = Comments:create({ post_id = post.id, user_id = author.id, body = "b" })
		for _, kind in ipairs({ "post_reply", "comment_reply" }) do
			Notifications:notify(author.id, comment.id, kind)
			assert.same(
				1,
				#Notifications:select("where kind = ? and comment_id = ?", kind, comment.id)
			)
		end
		Notifications:notify_mention(author.id, comment.id, nil)
		assert.same(
			1,
			#Notifications:select("where kind = 'mention' and comment_id = ?", comment.id)
		)
	end)

	describe("the table rebuild", function()
		it("preserves rows and keeps the partial unique indexes working", function()
			-- Re-running [114] rebuilds the tables again, so this exercises the
			-- copy path against real data rather than an empty schema.
			local voter = Users:create({
				user_name = "rebuild_voter",
				user_pass = "password",
				user_email = "rb@e.com",
			})
			Votes:set(voter.id, post.id, nil, 1)
			local before = #Votes:select("where user_id = ?", voter.id)
			assert.same(1, before)

			local score_before = Votes:post_score(post.id)
			local total_before = #Votes:select("where post_id = ?", post.id)

			migrations[114]()

			-- Every row survived the copy, with its direction intact.
			local kept = Votes:select("where user_id = ?", voter.id)
			assert.same(1, #kept)
			assert.same(1, tonumber(kept[1].upvote))
			assert.same(total_before, #Votes:select("where post_id = ?", post.id))
			assert.same(score_before, Votes:post_score(post.id))

			-- The [112] partial uniques were dropped with the old table and had
			-- to be recreated by hand; prove they are back.
			local now = db.format_date()
			local function raw_vote()
				return pcall(
					db.query,
					[[INSERT INTO votes (user_id, post_id, comment_id, upvote, created_at, updated_at)
						VALUES (?, ?, NULL, 1, ?, ?)]],
					voter.id,
					post.id,
					now,
					now
				)
			end
			assert.is_false((raw_vote()))
		end)

		it("leaves the expected indexes in place", function()
			local names = {}
			for _, r in ipairs(db.select("name FROM sqlite_master WHERE type = 'index'")) do
				names[r.name] = true
			end
			for _, expected in ipairs({
				"votes_user_id_idx",
				"votes_post_id_comment_id_upvote_idx",
				"votes_comment_id_upvote_idx",
				"votes_user_post_uniq",
				"votes_user_comment_uniq",
				"roles_subreddit_id_user_id_idx",
				"site_roles_user_id_idx",
				"notifications_user_id_idx",
			}) do
				assert.is_true(names[expected] == true, expected .. " is missing")
			end
		end)
	end)
end)

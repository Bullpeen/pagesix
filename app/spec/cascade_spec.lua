--- ON DELETE CASCADE spec (migration [115]).
--
-- The personal tables cascade off `users`, so the guarantee lives in the schema
-- rather than only in `Users:delete_account`. Authored content deliberately does
-- not: its policy is reassignment to the anonymous account, and a cascade there
-- would silently destroy other people's threads.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("delete cascade", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Roles = require("src.models.roles")
	local SiteRoles = require("src.models.site_roles")
	local Subscriptions = require("models.subscriptions")
	local SavedPosts = require("src.models.saved_posts")
	local HiddenPosts = require("src.models.hidden_posts")
	local Notifications = require("models.notifications")
	local PasswordResets = require("models.password_resets")

	local host, sub, post

	setup(function()
		require("spec.schema_helper")()
		host =
			Users:create({ user_name = "cas_host", user_pass = "password", user_email = "h@e.com" })
		sub = Forum:create({ name = "cascadesub", creator_id = host.id })
		post = Posts:create({
			user_id = host.id,
			sub_id = sub.id,
			title = "t",
			url = "https://e.example",
		})
	end)

	local seq = 0
	local function populated_user()
		seq = seq + 1
		local name = "cas_user" .. seq
		local user = Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@e.com",
		})
		Subscriptions:create({ user_id = user.id, subreddit_id = sub.id })
		SavedPosts:create({ user_id = user.id, post_id = post.id })
		HiddenPosts:create({ user_id = user.id, post_id = post.id })
		Notifications:notify(user.id, nil, "post_reply")
		PasswordResets:issue(user.id)
		db.insert("oauth_identities", {
			user_id = user.id,
			provider = "fake",
			provider_user_id = "p" .. seq,
			created_at = db.format_date(),
			updated_at = db.format_date(),
		})
		Roles:assign(sub.id, user.id, "member")
		SiteRoles:grant(user.id, "admin")
		return user
	end

	local PERSONAL = {
		"subscriptions",
		"saved_posts",
		"hidden_posts",
		"notifications",
		"password_resets",
		"oauth_identities",
		"roles",
		"site_roles",
	}

	local function counts_for(user_id)
		local out = {}
		for _, t in ipairs(PERSONAL) do
			out[t] = tonumber(
				db.select("count(*) AS n FROM " .. t .. " WHERE user_id = ?", user_id)[1].n
			)
		end
		return out
	end

	it("removes every personal row when the user row is deleted directly", function()
		local user = populated_user()
		for name, n in pairs(counts_for(user.id)) do
			assert.is_true(n > 0, name .. " should have been populated")
		end

		-- A raw delete, not Users:delete_account -- the point is that the schema
		-- enforces this even when the model method is not the one doing it.
		db.query("DELETE FROM users WHERE id = ?", user.id)

		for name, n in pairs(counts_for(user.id)) do
			assert.same(0, n, name .. " should have cascaded")
		end
	end)

	it("refuses to delete a user who still has authored content", function()
		local author = populated_user()
		Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "authored",
			url = "https://e.example/a",
		})

		-- posts/comments/votes/modlog stay NO ACTION on purpose: their policy is
		-- reassignment, so the delete has to fail rather than take the thread
		-- down with it.
		local ok = pcall(db.query, "DELETE FROM users WHERE id = ?", author.id)
		assert.is_false(ok)
		assert.is_truthy(Users:find(author.id))
	end)

	it("Users:delete_account still reassigns content and clears personal rows", function()
		local leaver = populated_user()
		local kept = Posts:create({
			user_id = leaver.id,
			sub_id = sub.id,
			title = "survives",
			url = "https://e.example/s",
		})
		local comment = Comments:create({ post_id = post.id, user_id = leaver.id, body = "stays" })

		assert.is_true(Users:delete_account(leaver.id))

		local anon = Users:anonymous()
		assert.same(tonumber(anon.id), tonumber(Posts:find(kept.id).user_id))
		assert.same(tonumber(anon.id), tonumber(Comments:find(comment.id).user_id))
		for name, n in pairs(counts_for(leaver.id)) do
			assert.same(0, n, name .. " should be gone")
		end
	end)

	it("has dropped the never-read users.deleted_at column", function()
		for _, column in ipairs(db.query("PRAGMA table_info(users)")) do
			assert.are_not.same("deleted_at", column.name)
		end
		-- The soft-delete columns that *are* used stay put.
		local function has_column(table_name, wanted)
			for _, column in ipairs(db.query("PRAGMA table_info(" .. table_name .. ")")) do
				if column.name == wanted then
					return true
				end
			end
			return false
		end
		assert.is_true(has_column("forum", "deleted_at"))
		assert.is_true(has_column("posts", "deleted"))
		assert.is_true(has_column("comments", "deleted"))
	end)
end)

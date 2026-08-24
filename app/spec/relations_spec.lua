--- Relations + moderator-list spec.
--
-- Covers the two model relations that were silently filtering nothing (they
-- asked for `deleted_at = nil`, a key that is simply absent in Lua, on tables
-- whose soft-delete column is the integer `deleted`), and `Roles:moderators`,
-- which now feeds the subreddit sidebar list that never used to render.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("model relations", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Roles = require("src.models.roles")

	setup(function()
		require("spec.schema_helper")()
	end)

	local seq = 0
	local function make_user(prefix)
		seq = seq + 1
		local name = prefix .. seq
		return Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@e.com",
		})
	end

	it("authored_posts excludes soft-deleted posts", function()
		local author = make_user("rel_author")
		local sub = Forum:create({ name = "relsub" .. seq, creator_id = author.id })
		local kept = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "kept",
			url = "https://e.example/1",
		})
		local gone = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "gone",
			url = "https://e.example/2",
		})
		gone:update({ deleted = 1 })

		local rows = author:get_authored_posts()
		assert.same(1, #rows)
		assert.same(tonumber(kept.id), tonumber(rows[1].id))
	end)

	it("authored_comments excludes soft-deleted comments", function()
		local author = make_user("rel_commenter")
		local sub = Forum:create({ name = "relsub" .. seq, creator_id = author.id })
		local post = Posts:create({
			user_id = author.id,
			sub_id = sub.id,
			title = "t",
			url = "https://e.example/3",
		})
		Comments:create({ post_id = post.id, user_id = author.id, body = "kept" })
		local gone = Comments:create({ post_id = post.id, user_id = author.id, body = "gone" })
		gone:update({ deleted = 1 })

		local rows = author:get_authored_comments()
		assert.same(1, #rows)
		assert.same("kept", rows[1].body)
	end)

	describe("Roles:moderators", function()
		it("lists owners before moderators, and nobody else", function()
			local owner = make_user("mod_owner")
			local mod = make_user("mod_mod")
			local bystander = make_user("mod_none")
			local sub = Forum:create({ name = "modsub" .. seq, creator_id = owner.id })
			Forum:add_owner(sub.id, owner.id)
			Forum:add_moderator(sub.id, mod.id)
			Roles:assign(sub.id, bystander.id, "member")

			local names = Roles:moderators(sub.id)
			assert.same({ owner.user_name, mod.user_name }, names)
		end)

		it("returns an empty list for a subreddit with no roles", function()
			assert.same({}, Roles:moderators(nil))
		end)

		it("renders the sidebar Moderators list on a subreddit page", function()
			local owner = make_user("side_owner")
			local sub = Forum:create({ name = "sidesub" .. seq, creator_id = owner.id })
			Forum:add_owner(sub.id, owner.id)

			local app = require("app")
			local status, body = simulate_request(app, "/r/" .. sub.name, { method = "GET" })
			assert.same(200, status)
			-- The block existed but nothing ever assigned `moderators`, so it
			-- never rendered before.
			assert.truthy(body:find("Moderators", 1, true))
			assert.truthy(body:find("/user/" .. owner.user_name, 1, true))
		end)
	end)
end)

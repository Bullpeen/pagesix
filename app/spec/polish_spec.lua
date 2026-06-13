--- Polish spec: markdown rendering, subreddit creation constraints,
--- user-filtered listings, and index usage.

local use_test_env = require("lapis.spec").use_test_env
local db = require("lapis.db")

describe("markdown rendering", function()
	local render = require("src.utils.markdown")

	it("renders markdown to html", function()
		assert.truthy(render("**bold**"):find("<strong>bold</strong>", 1, true))
	end)

	it("sanitizes embedded raw html (no script injection)", function()
		assert.is_nil(render("hi <script>alert(1)</script>"):find("<script", 1, true))
	end)

	it("returns empty string for nil/empty input", function()
		assert.same("", render(nil))
		assert.same("", render(""))
	end)
end)

describe("subreddit + user-profile polish", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")

	setup(function()
		require("spec.schema_helper")()
	end)

	it("rejects reserved and too-short subreddit names via the Lapis constraint", function()
		local s1, e1 = Forum:create({ name = "all", creator_id = 1 })
		assert.is_nil(s1)
		assert.same("Subreddit name is reserved", e1)

		local s2, e2 = Forum:create({ name = "a", creator_id = 1 })
		assert.is_nil(s2)
		assert.truthy(e2)
	end)

	it("creates a valid subreddit", function()
		local u = Users:create({
			user_name = "sub_creator",
			user_pass = "password",
			user_email = "s@e.com",
		})
		local s = Forum:create({ name = "lua_lang", description = "Lua", creator_id = u.id })
		assert.same("lua_lang", s.name)
	end)

	it("filters posts and comments by user (with markdown bodies)", function()
		local u1 = Users:create({
			user_name = "profile_a",
			user_pass = "password",
			user_email = "pa@e.com",
		})
		local u2 = Users:create({
			user_name = "profile_b",
			user_pass = "password",
			user_email = "pb@e.com",
		})
		local f = Forum:create({ name = "profiles_sub", creator_id = u1.id })
		Posts:create({ user_id = u1.id, sub_id = f.id, title = "by a", url = "https://a.example" })
		local p2 = Posts:create({
			user_id = u2.id,
			sub_id = f.id,
			title = "by b",
			url = "https://b.example",
		})
		Comments:create({ post_id = p2.id, user_id = u1.id, body = "a comment **here**" })

		local a_posts = Posts:get_listing({ user_id = u1.id })
		assert.same(1, #a_posts)
		assert.same("by a", a_posts[1].title)

		local a_comments = Comments:by_user(u1.id)
		assert.same(1, #a_comments)
		assert.truthy(a_comments[1].body_html:find("<strong>here</strong>", 1, true))
	end)

	it("uses an index for the vote-count aggregate (migration [5])", function()
		local plan = db.query(
			"EXPLAIN QUERY PLAN SELECT COUNT(*) FROM votes v WHERE v.post_id = 1 AND v.comment_id IS NULL"
		)
		local text = ""
		for _, row in ipairs(plan) do
			text = text .. " " .. tostring(row.detail)
		end
		assert.truthy(text:upper():find("INDEX", 1, true), "expected an index scan, got:" .. text)
	end)

	it("uses a covering index for the full vote-count subquery", function()
		local plan = db.query(
			"EXPLAIN QUERY PLAN SELECT COUNT(*) FROM votes WHERE post_id = 1 AND comment_id IS NULL AND upvote = 1"
		)
		local text = ""
		for _, row in ipairs(plan) do
			text = text .. " " .. tostring(row.detail)
		end
		assert.truthy(
			text:upper():find("COVERING INDEX", 1, true),
			"expected covering index, got:" .. text
		)
	end)
end)

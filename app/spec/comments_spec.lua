--- Comment threading + creation spec

local use_test_env = require("lapis.spec").use_test_env

describe("comment threading", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")

	setup(function()
		require("spec.schema_helper")()
	end)

	local function scaffold(name)
		local u = Users:create({ user_name = name, user_pass = "password", user_email = name .. "@e.com" })
		local f = Forum:create({ name = name .. "_sub", creator_id = u.id })
		local p = Posts:create({ user_id = u.id, sub_id = f.id, title = "t", url = "https://e.example" })
		return u, p
	end

	it("orders the thread depth-first with depth levels", function()
		local u, p = scaffold("threader")
		local root = Comments:create({ post_id = p.id, user_id = u.id, body = "root" })
		local child = Comments:create({ post_id = p.id, user_id = u.id, body = "child", parent_comment_id = root.id })
		Comments:create({ post_id = p.id, user_id = u.id, body = "grandchild", parent_comment_id = child.id })
		Comments:create({ post_id = p.id, user_id = u.id, body = "root2" })

		local order, depths = {}, {}
		for _, c in ipairs(Comments:thread(p.id)) do
			table.insert(order, c.body)
			table.insert(depths, tonumber(c.depth))
		end

		assert.same({ "root", "child", "grandchild", "root2" }, order)
		assert.same({ 0, 1, 2, 0 }, depths)
	end)

	it("rejects an empty comment via the model constraint", function()
		local u, p = scaffold("emptier")
		local c, err = Comments:create({ post_id = p.id, user_id = u.id, body = "" })
		assert.is_nil(c)
		assert.same("Comment cannot be empty", err)
	end)

	it("keeps deleted comments in the thread as [deleted]", function()
		local u, p = scaffold("deleter")
		Comments:create({ post_id = p.id, user_id = u.id, body = "keep" })
		local gone = Comments:create({ post_id = p.id, user_id = u.id, body = "gone" })
		gone:update({ deleted = 1 })

		local thread = Comments:thread(p.id)
		assert.same(2, #thread) -- node kept so replies aren't orphaned
		local del
		for _, c in ipairs(thread) do
			if c.id == gone.id then del = c end
		end
		assert.same("[deleted]", del.body_html)
		assert.same("[deleted]", del.author)
	end)

	describe("permalink_thread", function()
		local child, grandchild

		setup(function()
			local u, p = scaffold("permalink")
			-- comments are UNIQUE on (user_id, post_id, parent_comment_id), so the
			-- extra root/sibling must come from a different user.
			local u2 = Users:create({ user_name = "permalink_other", user_pass = "password", user_email = "po@e.com" })
			local root = Comments:create({ post_id = p.id, user_id = u.id, body = "perma-root" })
			child = Comments:create({ post_id = p.id, user_id = u.id, body = "perma-child", parent_comment_id = root.id })
			grandchild = Comments:create({ post_id = p.id, user_id = u.id, body = "perma-gc", parent_comment_id = child.id })
			Comments:create({ post_id = p.id, user_id = u2.id, body = "perma-root2" }) -- unrelated root
			Comments:create({ post_id = p.id, user_id = u2.id, body = "perma-sibling", parent_comment_id = root.id }) -- child's sibling
		end)

		local function bodies(rows)
			local out = {}
			for i, r in ipairs(rows) do out[i] = r.body end
			return out
		end

		it("returns the focused comment + its subtree, no ancestors or siblings", function()
			local rows = Comments:permalink_thread(child.id, 0)
			assert.same({ "perma-child", "perma-gc" }, bodies(rows))
			assert.same({ 0, 1 }, { rows[1].depth, rows[2].depth })
		end)

		it("includes one ancestor (shifting depth) with context=1", function()
			local rows = Comments:permalink_thread(child.id, 1)
			assert.same({ "perma-root", "perma-child", "perma-gc" }, bodies(rows))
			assert.same({ 0, 1, 2 }, { rows[1].depth, rows[2].depth, rows[3].depth })
		end)

		it("walks up multiple ancestors and clamps to the root", function()
			local rows = Comments:permalink_thread(grandchild.id, 10)
			assert.same({ "perma-root", "perma-child", "perma-gc" }, bodies(rows))
		end)

		it("returns an empty list for an unknown comment", function()
			assert.same({}, Comments:permalink_thread(999999, 0))
		end)
	end)
end)

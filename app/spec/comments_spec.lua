--- Comment threading + creation spec

local use_test_env = require("lapis.spec").use_test_env

describe("comment threading", function()
	use_test_env()

	local migrations = require("migrations")
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
end)

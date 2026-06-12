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
		migrations[1]()
		migrations[2]()
		migrations[3]()
		migrations[4]()
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

	it("excludes deleted comments from the thread", function()
		local u, p = scaffold("deleter")
		Comments:create({ post_id = p.id, user_id = u.id, body = "keep" })
		local gone = Comments:create({ post_id = p.id, user_id = u.id, body = "gone" })
		gone:update({ deleted = 1 })

		local bodies = {}
		for _, c in ipairs(Comments:thread(p.id)) do
			table.insert(bodies, c.body)
		end
		assert.same({ "keep" }, bodies)
	end)
end)

--- @mention spec: extraction/linkify (pure), resolution, and notification wiring
--- for both comment and post-body mentions, plus the [105] notifications rebuild.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("@mentions", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Notifications = require("models.notifications")
	local Mentions = require("src.utils.mentions")
	local app = require("app")

	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	local function POST(url, params, user)
		params = params or {}
		params.csrf_token = CSRF_TOKEN
		return simulate_request(app, url, {
			method = "POST",
			post = params,
			session = user and { current_user = user } or nil,
			cookies = { [CSRF_COOKIE] = CSRF_KEY },
		})
	end

	local function make_user(name, reputation)
		local u = Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
		if reputation then
			u:update({ reputation = reputation })
		end
		return u
	end

	setup(function()
		require("spec.schema_helper")()
	end)

	describe("extract (pure)", function()
		it("pulls distinct @names and skips emails + code", function()
			assert.same({ "alice", "bob" }, Mentions.extract("hi @alice and @bob and @alice"))
			assert.same({}, Mentions.extract("email bob@example.com is not a mention"))
			assert.same({}, Mentions.extract("`@incode` stays code"))
			assert.same({}, Mentions.extract("```\n@fenced\n```"))
		end)
	end)

	describe("linkify (pure)", function()
		it("rewrites mentions to markdown profile links, leaving emails alone", function()
			assert.same("hey [@alice](/user/alice)!", Mentions.linkify("hey @alice!"))
			assert.same("mail bob@example.com", Mentions.linkify("mail bob@example.com"))
		end)
	end)

	describe("resolve", function()
		it("returns only existing users and skips the excluded id", function()
			local a = make_user("m_alice")
			make_user("m_bob")
			local resolved = Mentions.resolve("@m_alice @m_bob @ghost", a.id)
			local names = {}
			for _, u in ipairs(resolved) do
				names[u.user_name] = true
			end
			assert.is_nil(names["m_alice"]) -- excluded (self)
			assert.is_true(names["m_bob"])
			assert.is_nil(names["ghost"]) -- no such user
		end)
	end)

	describe("comment mentions", function()
		it("notifies a mentioned user, with a comment permalink", function()
			local author = make_user("m_author", 50)
			local target = make_user("m_target")
			local sub = Forum:create({ name = "m_sub", creator_id = author.id })
			local post = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "mention host",
				url = "https://m.example",
			})

			POST("/post/" .. post.id .. "/comment", { body = "hey @m_target look" }, "m_author")

			assert.same(1, Notifications:unread_count(target.id))
			local list = Notifications:for_user(target.id)
			assert.same("mention", list[1].kind)
			assert.same("m_author", list[1].author)
			assert.truthy(list[1].permalink:find("/comments/" .. post.id, 1, true))
		end)

		it("does not double-notify when you reply to and mention the same person", function()
			local op = make_user("m_op")
			make_user("m_replier", 50) -- signs in via the session below
			local sub = Forum:create({ name = "m_sub2", creator_id = op.id })
			local post = Posts:create({
				user_id = op.id,
				sub_id = sub.id,
				title = "dbl",
				url = "https://d.example",
			})
			local parent = Comments:create({ post_id = post.id, user_id = op.id, body = "parent" })

			POST("/post/" .. post.id .. "/comment", {
				body = "@m_op thanks",
				parent_comment_id = tostring(parent.id),
			}, "m_replier")

			assert.same(1, Notifications:unread_count(op.id)) -- one, not two
		end)
	end)

	describe("post-body mentions", function()
		it("notifies a mentioned user, with a post permalink", function()
			local author = make_user("m_poster", 50)
			local target = make_user("m_readee")
			Forum:create({ name = "m_sub3", creator_id = author.id })

			POST("/submit", {
				subreddit = "m_sub3",
				title = "self post with mention",
				body = "ping @m_readee in the body",
			}, "m_poster")

			assert.same(1, Notifications:unread_count(target.id))
			local n = Notifications:for_user(target.id)[1]
			assert.same("mention", n.kind)
			local post = Posts:find({ title = "self post with mention" })
			assert.truthy(n.permalink:find("/comments/" .. post.id, 1, true))
		end)
	end)

	describe("migration [105]", function()
		it("kept comment_id nullable and added post_id", function()
			local db = require("lapis.db")
			local cols = {}
			for _, c in ipairs(db.query("PRAGMA table_info(notifications)")) do
				cols[c.name] = c
			end
			assert.is_truthy(cols.post_id)
			assert.same(0, tonumber(cols.comment_id.notnull)) -- nullable now
		end)
	end)
end)

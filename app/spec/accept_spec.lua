--- Accept-answer spec: the is_question flag, the accept/unaccept toggle and its
--- authorization (OP or accept_answer privilege), and the listing fields.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("accept answer", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
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

	local op, answerer, sub
	setup(function()
		require("spec.schema_helper")()
		op = make_user("ans_op", 50)
		answerer = make_user("ans_answerer", 50)
		sub = Forum:create({ name = "ans_sub", creator_id = op.id })
	end)

	local function question_with_answer(title)
		local post = Posts:create({
			user_id = op.id,
			sub_id = sub.id,
			title = title,
			url = "https://q.example/" .. title,
			is_question = 1,
		})
		local answer = Comments:create({
			post_id = post.id,
			user_id = answerer.id,
			body = "the answer",
		})
		return post, answer
	end

	it("submit records the is_question flag", function()
		POST("/submit", {
			subreddit = "ans_sub",
			title = "how do i lua?",
			body = "help please",
			is_question = "1",
		}, "ans_op")
		assert.same(1, tonumber(Posts:find({ title = "how do i lua?" }).is_question))
	end)

	it("lets the OP accept and then unaccept an answer (toggle)", function()
		local post, answer = question_with_answer("op-accepts")
		assert.is_nil(Posts:find(post.id).accepted_comment_id)

		POST("/comment/" .. answer.id .. "/accept", {}, "ans_op")
		assert.same(answer.id, tonumber(Posts:find(post.id).accepted_comment_id))

		-- toggling the same comment clears it
		POST("/comment/" .. answer.id .. "/accept", {}, "ans_op")
		assert.is_nil(Posts:find(post.id).accepted_comment_id)
	end)

	it("lets a moderator (accept_answer privilege) accept", function()
		local post, answer = question_with_answer("mod-accepts")
		local mod = make_user("ans_mod")
		Forum:add_moderator(sub.id, mod.id)

		POST("/comment/" .. answer.id .. "/accept", {}, "ans_mod")
		assert.same(answer.id, tonumber(Posts:find(post.id).accepted_comment_id))
	end)

	it("ignores accept from a random non-OP, non-moderator", function()
		local post, answer = question_with_answer("stranger-denied")
		make_user("ans_stranger", 50)

		POST("/comment/" .. answer.id .. "/accept", {}, "ans_stranger")
		assert.is_nil(Posts:find(post.id).accepted_comment_id)
	end)

	it("exposes is_question/accepted_comment_id in get_listing", function()
		local post, answer = question_with_answer("listed")
		POST("/comment/" .. answer.id .. "/accept", {}, "ans_op")

		local row
		for _, r in ipairs(Posts:get_listing(sub.id)) do
			if r.id == post.id then
				row = r
			end
		end
		assert.is_truthy(row)
		assert.same(1, tonumber(row.is_question))
		assert.same(answer.id, tonumber(row.accepted_comment_id))
	end)
end)

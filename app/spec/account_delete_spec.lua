--- Account deletion spec.
-- `Users:delete_account` keeps authored content (reattributed to the anonymous
-- account) and destroys everything personal. These assert both halves, plus the
-- HTTP flow that fronts it.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request
local db = require("lapis.db")

describe("account deletion", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local Subscriptions = require("models.subscriptions")
	local Notifications = require("models.notifications")
	local SavedPosts = require("src.models.saved_posts")

	setup(function()
		require("spec.schema_helper")()
	end)

	local seq = 0
	local function make_user(prefix)
		seq = seq + 1
		local name = (prefix or "leaver") .. seq
		return Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
	end

	-- The HTTP flow verifies the password, so those users need a real bcrypt
	-- digest rather than the plaintext the model-level cases store.
	local function make_user_with_password(prefix, plain)
		seq = seq + 1
		local name = (prefix or "leaver") .. seq
		return Users:create({
			user_name = name,
			user_pass = require("src.utils.password").hash(plain),
			user_email = name .. "@example.com",
		})
	end

	describe("Users:delete_account", function()
		it("keeps posts and comments, reattributed to the anonymous account", function()
			local leaver, stayer = make_user(), make_user("stayer")
			local sub = Forum:create({ name = "quitting" .. seq, creator_id = stayer.id })
			local post = Posts:create({
				user_id = leaver.id,
				sub_id = sub.id,
				title = "still here",
				url = "https://example.com/keep",
			})
			local comment = Comments:create({
				post_id = post.id,
				user_id = leaver.id,
				body = "and so is this",
			})

			assert.is_true(Users:delete_account(leaver.id))

			local anon = Users:anonymous()
			assert.is_truthy(anon)
			-- Content survives, and the thread still reads.
			assert.same("still here", Posts:find(post.id).title)
			assert.same("and so is this", Comments:find(comment.id).body)
			assert.same(tonumber(anon.id), tonumber(Posts:find(post.id).user_id))
			assert.same(tonumber(anon.id), tonumber(Comments:find(comment.id).user_id))
			-- The account itself is gone.
			assert.is_nil(Users:find(leaver.id))
		end)

		it("destroys everything personal", function()
			local leaver = make_user()
			local other = make_user("host")
			local sub = Forum:create({ name = "personal" .. seq, creator_id = other.id })
			local post = Posts:create({
				user_id = other.id,
				sub_id = sub.id,
				title = "x",
				url = "https://example.com/p",
			})
			Subscriptions:create({ user_id = leaver.id, subreddit_id = sub.id })
			SavedPosts:create({ user_id = leaver.id, post_id = post.id })
			Notifications:create({ user_id = leaver.id, post_id = post.id, kind = "post_reply" })

			assert.is_true(Users:delete_account(leaver.id))

			for _, t in ipairs({ "subscriptions", "saved_posts", "notifications" }) do
				local rows =
					db.select("count(*) AS n FROM " .. t .. " WHERE user_id = ?", leaver.id)
				assert.same(0, tonumber(rows[1].n), t .. " should be empty")
			end
		end)

		it("keeps a departing user's votes so scores do not shift", function()
			local leaver, author = make_user(), make_user("author")
			local sub = Forum:create({ name = "voting" .. seq, creator_id = author.id })
			local post = Posts:create({
				user_id = author.id,
				sub_id = sub.id,
				title = "scored",
				url = "https://example.com/v",
			})
			Votes:cast(leaver.id, post.id, nil, 1)
			local before = Votes:post_score(post.id)

			assert.is_true(Users:delete_account(leaver.id))

			assert.same(before, Votes:post_score(post.id))
		end)

		it("hands a departing owner's subreddit to the anonymous account", function()
			local owner = make_user("owner")
			local sub = Forum:create({ name = "orphan" .. seq, creator_id = owner.id })
			Forum:add_owner(sub.id, owner.id)

			assert.is_true(Users:delete_account(owner.id))

			-- The community survives rather than vanishing with its creator.
			local kept = Forum:find(sub.id)
			assert.is_truthy(kept)
			assert.same(tonumber(Users:anonymous().id), tonumber(kept.creator_id))
		end)

		it("refuses to delete the anonymous account itself", function()
			local anon = Users:ensure_anonymous()
			local ok, err = Users:delete_account(anon.id)
			assert.is_nil(ok)
			assert.truthy(tostring(err):find("anonymous", 1, true))
			assert.is_truthy(Users:anonymous())
		end)

		it("reports a missing user instead of raising", function()
			local ok, err = Users:delete_account(999999)
			assert.is_nil(ok)
			assert.same("No such user", err)
		end)
	end)

	describe("POST /account/delete", function()
		local app = require("app")
		local encoding = require("lapis.util.encoding")
		local config = require("lapis.config").get()
		local CSRF_COOKIE = config.session_name .. "_token"
		local CSRF_KEY = "spec-csrf-key"
		local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

		local function POST(params, user)
			params = params or {}
			params.csrf_token = params.csrf_token or CSRF_TOKEN
			return simulate_request(app, "/account/delete", {
				method = "POST",
				post = params,
				session = user and { current_user = user } or nil,
				cookies = { [CSRF_COOKIE] = CSRF_KEY },
			})
		end

		it("redirects anonymous visitors to log in", function()
			local status, _, headers = simulate_request(app, "/account/delete", { method = "GET" })
			assert.same(302, status)
			assert.truthy(tostring(headers.location):find("/login", 1, true))
		end)

		it("renders the confirmation form for the signed-in user", function()
			local user = make_user_with_password("form", "password")
			local status, body = simulate_request(app, "/account/delete", {
				method = "GET",
				session = { current_user = user.user_name },
			})
			assert.same(200, status)
			assert.truthy(body:find("Delete your account", 1, true))
			-- Names what happens to their content, and what to type to confirm.
			assert.truthy(body:find(Users.ANONYMOUS, 1, true))
			assert.truthy(body:find(user.user_name, 1, true))
			assert.truthy(body:find('name="password"', 1, true))
		end)

		it("links to deletion from your own profile, but not from someone else's", function()
			local mine = make_user_with_password("mine", "password")
			local theirs = make_user("theirs")

			local _, own = simulate_request(app, "/user/" .. mine.user_name, {
				method = "GET",
				session = { current_user = mine.user_name },
			})
			assert.truthy(own:find("/account/delete", 1, true))

			local _, other = simulate_request(app, "/user/" .. theirs.user_name, {
				method = "GET",
				session = { current_user = mine.user_name },
			})
			assert.is_nil(other:find("/account/delete", 1, true))
		end)

		it("rejects a mistyped username without deleting anything", function()
			local user = make_user_with_password("typo", "password")
			local status, body =
				POST({ confirm = "not-my-name", password = "password" }, user.user_name)
			assert.same(200, status)
			assert.truthy(body:find("Type your username exactly", 1, true))
			assert.is_truthy(Users:find(user.id))
		end)

		it("rejects a wrong password without deleting anything", function()
			local user = make_user_with_password("badpass", "password")
			local status, body =
				POST({ confirm = user.user_name, password = "wrong" }, user.user_name)
			assert.same(200, status)
			assert.truthy(body:find("password is not correct", 1, true))
			assert.is_truthy(Users:find(user.id))
		end)

		it("deletes the account and logs the visitor out", function()
			local user = make_user_with_password("gone", "password")
			local status, _, headers =
				POST({ confirm = user.user_name, password = "password" }, user.user_name)
			assert.same(302, status)
			assert.is_not_nil(headers.location)
			assert.is_nil(Users:find(user.id))
		end)
	end)
end)

--- Tags spec: normalization, set/replace, the listing filter, the submit-action
--- wiring, and the /t/:tag page.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("tags", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Tags = require("src.models.tags")
	local app = require("app")

	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	local owner, sub
	setup(function()
		require("spec.schema_helper")()
		owner = Users:create({
			user_name = "tag_owner",
			user_pass = "password",
			user_email = "t@e.com",
			-- enough reputation to skip the approval queue
		})
		owner:update({ reputation = 50 })
		sub = Forum:create({ name = "tag_sub", creator_id = owner.id })
	end)

	local function new_post(title)
		return Posts:create({
			user_id = owner.id,
			sub_id = sub.id,
			title = title,
			url = "https://e.example/" .. title,
		})
	end

	describe("normalize", function()
		it("splits on commas/space, lowercases, and dedupes", function()
			assert.same({ "lua", "web" }, Tags.normalize("Lua, Web"))
			assert.same({ "lua", "web" }, Tags.normalize("lua web lua")) -- dedupe
		end)

		it("treats whitespace as a separator and slugifies in-token punctuation", function()
			-- spaces separate tags; punctuation inside a token becomes a hyphen
			assert.same({ "hello", "world" }, Tags.normalize("Hello World!"))
			assert.same({ "foo-bar" }, Tags.normalize("foo.bar"))
			assert.same({}, Tags.normalize("   "))
			assert.same({}, Tags.normalize(nil))
		end)

		it("caps at MAX_PER_POST", function()
			local out = Tags.normalize("a b c d e f g h")
			assert.same(Tags.MAX_PER_POST, #out)
		end)
	end)

	describe("set_for_post / for_post", function()
		it("attaches tags and reads them back, replacing on re-set", function()
			local p = new_post("tagme")
			Tags:set_for_post(p.id, "alpha, beta")
			assert.same({ "alpha", "beta" }, Tags:for_post(p.id))
			-- re-setting replaces, not appends
			Tags:set_for_post(p.id, "gamma")
			assert.same({ "gamma" }, Tags:for_post(p.id))
		end)

		it("reuses an existing tag row rather than duplicating it", function()
			local p1, p2 = new_post("shareA"), new_post("shareB")
			Tags:set_for_post(p1.id, "shared")
			Tags:set_for_post(p2.id, "shared")
			assert.same(1, Tags:count("name = ?", "shared"))
		end)
	end)

	describe("listing filter", function()
		it("get_listing({ tag }) returns only posts with that tag", function()
			local tagged = new_post("filtered-in")
			local untagged = new_post("filtered-out")
			Tags:set_for_post(tagged.id, "findme")

			local titles = {}
			for _, row in ipairs(Posts:get_listing({ tag = "findme" })) do
				titles[row.title] = true
			end
			assert.is_true(titles["filtered-in"])
			assert.is_nil(titles["filtered-out"])
			assert.is_truthy(untagged)
		end)
	end)

	describe("submit + /t/:tag", function()
		it("submit attaches tags and the tag page lists the post", function()
			simulate_request(app, "/submit", {
				method = "POST",
				post = {
					subreddit = "tag_sub",
					title = "tagged via submit",
					url = "https://sub.example",
					tags = "Roadmap, news",
					csrf_token = CSRF_TOKEN,
				},
				session = { current_user = "tag_owner" },
				cookies = { [CSRF_COOKIE] = CSRF_KEY },
			})

			local post = Posts:find({ title = "tagged via submit" })
			assert.same({ "news", "roadmap" }, Tags:for_post(post.id))

			-- normalized lookup: /t/Roadmap resolves to the "roadmap" tag
			local status, body = simulate_request(app, "/t/Roadmap", { method = "GET" })
			assert.same(200, status)
			assert.truthy(body:find("tagged via submit", 1, true))
		end)
	end)
end)

--- OAuth spec: authorize-url building, link-or-create, and the start/callback
--- actions (the network `identify` step is stubbed).

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("oauth login", function()
	use_test_env()

	local Users = require("models.users")
	local Password = require("src.utils.password")
	local OAuth = require("src.utils.oauth")
	local OAuthIdentities = require("src.models.oauth_identities")
	local app = require("app")

	setup(function()
		require("spec.schema_helper")()
	end)

	describe("authorize_url", function()
		it("builds the provider URL with our params", function()
			local url = OAuth.authorize_url("fakeprov", "STATE123", "https://us.test/cb")
			assert.truthy(url:find("https://provider.test/authorize?", 1, true))
			assert.truthy(url:find("client_id=", 1, true))
			assert.truthy(url:find("state=STATE123", 1, true))
			assert.truthy(url:find("response_type=code", 1, true))
			assert.truthy(url:find("redirect_uri=", 1, true))
		end)

		it("returns nil for an unknown provider", function()
			assert.is_nil(OAuth.authorize_url("nope", "s", "u"))
			assert.is_nil(OAuth.provider("nope"))
		end)
	end)

	describe("link_or_create", function()
		it("creates a user + identity with an unusable password", function()
			local user = OAuth.link_or_create("fakeprov", {
				provider_user_id = 555,
				username = "octocat",
				email = "octo@cat.test",
			})
			assert.same("octocat", user.user_name)
			-- password is unusable (a hash of a random secret, not anything typed)
			assert.is_false(Password.verify("", user.user_pass))
			assert.is_truthy(
				OAuthIdentities:find({ provider = "fakeprov", provider_user_id = "555" })
			)
		end)

		it("returns the same user for a repeat identity (no duplicate)", function()
			local first =
				OAuth.link_or_create("fakeprov", { provider_user_id = 777, username = "dup" })
			local again =
				OAuth.link_or_create("fakeprov", { provider_user_id = 777, username = "dup" })
			assert.same(first.id, again.id)
			assert.same(
				1,
				OAuthIdentities:count("provider = ? AND provider_user_id = ?", "fakeprov", "777")
			)
		end)

		it("disambiguates a colliding username", function()
			Users:create({ user_name = "taken", user_pass = "password", user_email = "t@e.test" })
			local user =
				OAuth.link_or_create("fakeprov", { provider_user_id = 888, username = "taken" })
			assert.is_truthy(user)
			assert.are_not.same("taken", user.user_name) -- got a suffixed name
		end)
	end)

	describe("start action", function()
		it("redirects to the provider for a known provider", function()
			local status, _, headers = simulate_request(app, "/auth/fakeprov", { method = "GET" })
			assert.same(302, status)
			assert.truthy(headers.location:find("https://provider.test/authorize", 1, true))
		end)

		it("redirects unknown providers to login", function()
			local status, _, headers = simulate_request(app, "/auth/nope", { method = "GET" })
			assert.same(302, status)
			assert.truthy(headers.location:find("/login", 1, true))
		end)
	end)

	describe("callback action", function()
		local orig_identify
		before_each(function()
			orig_identify = OAuth.identify
		end)
		after_each(function()
			OAuth.identify = orig_identify
		end)

		it("signs in (creates) a user when state matches", function()
			OAuth.identify = function()
				return { provider_user_id = 4242, username = "callbackuser", email = "cb@u.test" }
			end
			local status, _, headers =
				simulate_request(app, "/auth/fakeprov/callback?code=abc&state=S", {
					method = "GET",
					session = { oauth_state = "S" },
				})
			assert.same(302, status)
			assert.truthy(headers.location:find("/", 1, true))
			assert.is_truthy(Users:find({ user_name = "callbackuser" }))
		end)

		it("rejects a mismatched state (no login)", function()
			OAuth.identify = function()
				error("identify should not be called on a bad state")
			end
			local status, _, headers =
				simulate_request(app, "/auth/fakeprov/callback?code=abc&state=WRONG", {
					method = "GET",
					session = { oauth_state = "S" },
				})
			assert.same(302, status)
			assert.truthy(headers.location:find("/login", 1, true))
		end)
	end)
end)

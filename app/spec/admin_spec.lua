--- Admin Control Panel spec: access control, user management, settings, and the
--- config-driven admin bootstrap. Drives the real app through simulate_request.

local use_test_env = require("lapis.spec").use_test_env
local simulate_request = require("lapis.spec.request").simulate_request

describe("admin control panel", function()
	use_test_env()

	local Users = require("models.users")
	local SiteRoles = require("src.models.site_roles")
	local SiteSettings = require("src.models.site_settings")
	local Privileges = require("src.utils.privileges")
	local app = require("app")

	-- Same CSRF (cookie, token) trick the integration spec uses.
	local encoding = require("lapis.util.encoding")
	local config = require("lapis.config").get()
	local CSRF_COOKIE = config.session_name .. "_token"
	local CSRF_KEY = "spec-csrf-key"
	local CSRF_TOKEN = encoding.encode_with_secret({ k = CSRF_KEY })

	local function GET(url, user)
		return simulate_request(app, url, {
			method = "GET",
			session = user and { current_user = user } or nil,
		})
	end
	local function POST(url, params, user)
		params = params or {}
		if params.csrf_token == nil then
			params.csrf_token = CSRF_TOKEN
		end
		return simulate_request(app, url, {
			method = "POST",
			post = params,
			session = user and { current_user = user } or nil,
			cookies = { [CSRF_COOKIE] = CSRF_KEY },
		})
	end

	local admin, plain
	setup(function()
		require("spec.schema_helper")()
		admin =
			Users:create({ user_name = "boss", user_pass = "password", user_email = "boss@e.com" })
		plain =
			Users:create({ user_name = "pleb", user_pass = "password", user_email = "pleb@e.com" })
		SiteRoles:grant(admin.id, "admin")
	end)

	describe("access control", function()
		it("redirects anonymous visitors to login", function()
			assert.same(302, (GET("/admin")))
		end)

		it("forbids logged-in non-admins (403)", function()
			assert.same(403, (GET("/admin", "pleb")))
			assert.same(403, (GET("/admin/users", "pleb")))
			assert.same(403, (GET("/admin/settings", "pleb")))
		end)

		it("renders the dashboard for an admin", function()
			local status, body = GET("/admin", "boss")
			assert.same(200, status)
			assert.truthy(body:find("Admin Control Panel", 1, true))
		end)
	end)

	describe("user management", function()
		it("grants then revokes the admin role", function()
			assert.is_false(SiteRoles:is_admin(plain.id))
			POST("/admin/users", { user_id = plain.id, op = "grant" }, "boss")
			assert.is_true(SiteRoles:is_admin(plain.id))
			POST("/admin/users", { user_id = plain.id, op = "revoke" }, "boss")
			assert.is_false(SiteRoles:is_admin(plain.id))
		end)

		it("won't let an admin revoke their own role (no self-lockout)", function()
			assert.is_true(SiteRoles:is_admin(admin.id))
			POST("/admin/users", { user_id = admin.id, op = "revoke" }, "boss")
			assert.is_true(SiteRoles:is_admin(admin.id))
		end)

		it("ignores grant/revoke from a non-admin", function()
			POST("/admin/users", { user_id = admin.id, op = "revoke" }, "pleb")
			assert.is_true(SiteRoles:is_admin(admin.id))
		end)
	end)

	describe("settings", function()
		it("upserts a site setting", function()
			POST("/admin/settings", { key = "site_title", value = "My Forum" }, "boss")
			assert.same("My Forum", SiteSettings:get("site_title"))
			POST("/admin/settings", { key = "site_title", value = "Renamed" }, "boss")
			assert.same("Renamed", SiteSettings:get("site_title"))
		end)

		it("get() falls back to a default for an unknown key", function()
			assert.same("fallback", SiteSettings:get("never_set", "fallback"))
		end)
	end)

	describe("config bootstrap", function()
		it("auto-grants admin to a configured username on first check", function()
			local founder = Users:create({
				user_name = "founder",
				user_pass = "password",
				user_email = "f@e.com",
			})
			assert.is_false(SiteRoles:is_admin(founder.id))
			config.admin_usernames = { "founder" }
			assert.is_true(Privileges.ensure_admin(founder))
			assert.is_true(SiteRoles:is_admin(founder.id)) -- persisted to site_roles
			config.admin_usernames = {} -- restore for other examples
		end)
	end)
end)

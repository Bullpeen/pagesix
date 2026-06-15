--- Pagesix config
-- @script pagesix.config

local config = require("lapis.config")

-- Maximum file size
local body_size = "1m"

-- Path to your local project files
local lua_path = "./src/?.lua;./src/?/init.lua;./libs/?.lua;./libs/?/init.lua"
local lua_cpath = ""

-- Forward the LuaRocks search paths (exported by `luarocks path` in
-- docker-entrypoint.sh) into OpenResty's lua_package_path/cpath. OpenResty's
-- default paths do NOT include the LuaRocks trees, so without this the nginx
-- workers cannot find rock modules (lapis, lpeg, lsqlite3, ...) and the server
-- fails to boot. Guarded so it is a no-op when the vars are unset.
if os.getenv("LUA_PATH") then
	lua_path = lua_path .. ";" .. os.getenv("LUA_PATH")
end
if os.getenv("LUA_CPATH") then
	lua_cpath = lua_cpath .. ";" .. os.getenv("LUA_CPATH")
end

-- Usernames allowed into the Admin Control Panel on first visit (one-time
-- bootstrap; thereafter admins grant each other the role from /admin/users).
-- Set ADMIN_USERNAMES to a comma-separated list, e.g. "alice,bob".
local function admin_usernames()
	local names = {}
	local raw = os.getenv("ADMIN_USERNAMES")
	if raw then
		for n in raw:gmatch("[^,]+") do
			names[#names + 1] = n:match("^%s*(.-)%s*$")
		end
	end
	return names
end

-- https://github.com/snap-cloud/snapCloud/blob/master/config.lua
-- config({'development', 'test'}, {
--     use_daemon = 'off',
--     -- site_name = 'dev | Snap Cloud',
--     port = os.getenv('PORT') or 8080,
--     mail_smtp_port = os.getenv('MAIL_SMTP_PORT') or 1025,
--     dns_resolver = '8.8.8.8',
--     code_cache = 'off',
--     num_workers = 1,
--     log_directive = 'stderr debug',
--     secret = os.getenv('SESSION_SECRET_BASE') or 'this is a secret',

--     -- development needs no special SSL or cert config.
--     -- primary_nginx_config = 'locations.conf',
--     -- empty string when no additional configs are included.
--     -- secondary_nginx_config = ''
-- })

config("development", {
	port = 80,
	body_size = body_size,
	lua_path = lua_path,
	lua_cpath = lua_cpath,
	server = "nginx",
	code_cache = "off",
	num_workers = "1",
	name = "[DEVEL] Page Six",
	session_name = "dev_app_session",
	secret = os.getenv("SESSION_SECRET") or "dev-insecure-secret-change-me",
	admin_usernames = admin_usernames(),
	measure_performance = true,
	sqlite = {
		database = "/var/data/dev.sqlite",
	},
	-- In-process RSS/Atom feed scheduler (src/utils/feed_scheduler.lua).
	-- `interval` = seconds between ticks; `base_interval` = min seconds between
	-- fetches of one healthy feed (failures back off exponentially).
	feed_scheduler = {
		enabled = true,
		interval = 900,
		base_interval = 900,
	},
})

config("test", {
	port = 8080,
	server = "nginx",
	code_cache = "off",
	num_workers = "1",
	session_name = "test_app_session",
	secret = "test-secret",
	admin_usernames = {},
	-- In-memory database so the test suite never touches dev/prod data.
	sqlite = {
		database = ":memory:",
	},
})

config("production", {
	port = 80,
	body_size = body_size,
	lua_path = lua_path,
	lua_cpath = lua_cpath,
	code_cache = "on",
	server = "nginx",
	num_workers = "3",
	name = "Page Six",
	session_name = "prod_app_session",
	secret = os.getenv("LAPIS_SECRET"),
	admin_usernames = admin_usernames(),
	logging = {
		requests = true,
		queries = false,
		server = true,
	},
	sqlite = {
		database = "/var/data/production.sqlite",
	},
	-- In-process RSS/Atom feed scheduler (src/utils/feed_scheduler.lua).
	feed_scheduler = {
		enabled = true,
		interval = 900,
		base_interval = 900,
	},
})

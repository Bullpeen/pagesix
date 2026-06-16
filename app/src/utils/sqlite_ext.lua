--- SQLite run-time loadable extensions
-- @module utils.sqlite_ext
--
-- Loads SQLite extension shared objects (the sqlean bundle and friends) into
-- the *same* lsqlite3 connection that Lapis runs every query on. Extensions are
-- a per-connection facility in SQLite, so they must be loaded on each nginx
-- worker's connection (done from app.lua's before_filter) -- loading them on a
-- separately opened handle would register nothing for the queries Lapis runs.
--
-- Lapis's sqlite backend (lapis.db.sqlite) keeps that connection as a private
-- module upvalue (`active_connection`) and exposes no accessor, so we reach it
-- by reading the upvalue off one of the backend's closures via the debug
-- library. lsqlite3's `conn:load_extension(path)` both flips on the loader and
-- loads the library, returning `true` on success or `false, errmsg` on failure.

local M = {}

-- Default extensions to load when SQLITE_EXTENSIONS is unset. The Dockerfile
-- installs the sqlean bundle here; it registers regexp / fuzzy / stats / text /
-- crypto / math / ... functions under the default entry point.
local DEFAULT_EXTENSIONS = { "/usr/local/lib/sqlite/sqlean.so" }

-- Resolve the extension paths to load. SQLITE_EXTENSIONS overrides the default:
-- a colon-separated list of `.so` paths, or an empty value to disable loading.
local function configured_paths()
	local raw = os.getenv("SQLITE_EXTENSIONS")
	if raw == nil then
		return DEFAULT_EXTENSIONS
	end
	local paths = {}
	for path in raw:gmatch("[^:]+") do
		paths[#paths + 1] = path
	end
	return paths
end

local function warn(msg)
	msg = "[sqlite_ext] " .. msg
	if ngx and ngx.log then
		ngx.log(ngx.ERR, msg) -- luacheck: ignore
	else
		io.stderr:write(msg .. "\n")
	end
end

-- True when `value` is an lsqlite3 connection handle (userdata exposing a
-- load_extension method). Indexing arbitrary userdata can raise, so guard it.
local function is_connection(value)
	if type(value) ~= "userdata" then
		return false
	end
	local ok, method = pcall(function()
		return value.load_extension
	end)
	return ok and type(method) == "function"
end

-- Pull the live lsqlite3 connection out of the Lapis sqlite backend. Returns
-- the userdata handle, or nil if the backend isn't sqlite / isn't connected.
local function raw_connection()
	local ok, backend = pcall(require, "lapis.db.sqlite")
	if not ok or type(backend) ~= "table" or type(backend.query) ~= "function" then
		return nil
	end
	-- `active_connection` is an upvalue shared by the backend's query/insert/...
	-- closures. Prefer matching it by name; fall back to any upvalue that quacks
	-- like an lsqlite3 handle in case a stripped build dropped the upvalue names.
	local fallback
	for i = 1, 60 do
		local name, value = debug.getupvalue(backend.query, i)
		if not name then
			break
		end
		if name == "active_connection" and value ~= nil then
			return value
		end
		if fallback == nil and is_connection(value) then
			fallback = value
		end
	end
	return fallback
end

local loaded = false

--- Load the configured SQLite extensions into Lapis's active connection.
-- Idempotent per process (pass `{ force = true }` to reload). Never raises;
-- returns true when every configured extension loaded (or none were
-- configured), false otherwise.
-- @param opts table optional, `{ force = boolean }`
-- @return boolean
function M.load(opts)
	opts = opts or {}
	if loaded and not opts.force then
		return true
	end

	local paths = configured_paths()
	if #paths == 0 then
		loaded = true
		return true
	end

	-- Force the backend to open its connection before we grab the handle.
	local db = require("lapis.db")
	pcall(db.query, "SELECT 1")

	local conn = raw_connection()
	if not conn then
		warn("could not access the lsqlite3 connection; extensions not loaded")
		return false
	end

	local all_ok = true
	for _, path in ipairs(paths) do
		local ok, err = conn:load_extension(path)
		if not ok then
			all_ok = false
			warn(("failed to load %q: %s"):format(path, err or "unknown error"))
		end
	end
	-- Re-disable the loader now that we are done (SQLite's secure default) so
	-- application SQL can't pull in further libraries via load_extension().
	pcall(conn.load_extension, conn)

	loaded = all_ok
	return all_ok
end

return M

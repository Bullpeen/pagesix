--- In-process RSS/Atom feed scheduler.
-- @module utils.feed_scheduler
--
-- Runs the live importer (utils.feed_import) on a timer instead of only on the
-- manual mod trigger (POST /r/:sub/feeds/refresh). Built for OpenResty:
-- `start()` registers an `ngx.timer.every`; each tick claims a short-lived
-- cross-worker lock in the `feed_scheduler` shared dict so exactly one worker
-- refreshes feeds at a time (the rest no-op), then delegates to
-- `feed_import.refresh_all`, which uses the non-blocking resty.http client and
-- conditional GET. Enable it per environment via the `feed_scheduler` config
-- block (see config.lua); it is a no-op outside OpenResty (CLI, tests).

local feed_import = require("src.utils.feed_import")

local M = {}

-- Defaults, overridable via the `feed_scheduler` config block.
M.defaults = {
	interval = 900, -- seconds between scheduler ticks
	base_interval = 900, -- min seconds between fetches of one (healthy) feed
	lock_ttl = 600, -- safety TTL so the lock self-heals if a worker dies
	dict = "feed_scheduler", -- lua_shared_dict name (see nginx.conf)
}

local started = false -- per-worker guard: register the timer at most once

local function log(level, msg)
	if ngx and ngx.log and level then
		ngx.log(level, "[feed_scheduler] " .. msg)
	end
end

--- Effective config: the `feed_scheduler` block merged over the defaults.
function M.config()
	local ok, cfg = pcall(function()
		return require("lapis.config").get()
	end)
	local fs = (ok and cfg and cfg.feed_scheduler) or {}
	return {
		enabled = fs.enabled and true or false,
		interval = tonumber(fs.interval) or M.defaults.interval,
		base_interval = tonumber(fs.base_interval) or M.defaults.base_interval,
		lock_ttl = tonumber(fs.lock_ttl) or M.defaults.lock_ttl,
		dict = fs.dict or M.defaults.dict,
	}
end

-- The cross-worker lock lives in a shared dict so only one worker refreshes per
-- tick. `:add` is atomic create-if-absent; the TTL means a crashed worker can't
-- wedge the lock. With no shared dict (single worker / dev), just run.
local function lock_dict(opts)
	return ngx and ngx.shared and ngx.shared[opts.dict] or nil
end

--- @treturn boolean whether this worker may run this tick
function M.acquire_lock(opts)
	local dict = lock_dict(opts)
	if not dict then
		return true
	end
	return dict:add("refresh_lock", true, opts.lock_ttl) == true
end

function M.release_lock(opts)
	local dict = lock_dict(opts)
	if dict then
		dict:delete("refresh_lock")
	end
end

--- One scheduled pass: claim the lock, refresh due feeds, release.
-- @treturn number|nil imported, or nil if another worker held the lock / on error
function M.run_once(opts)
	opts = opts or M.config()
	if not M.acquire_lock(opts) then
		return nil
	end

	local ok, imported, checked = pcall(feed_import.refresh_all, opts.base_interval)
	M.release_lock(opts)

	if not ok then
		log(ngx and ngx.ERR, "refresh failed: " .. tostring(imported))
		return nil
	end
	if (checked or 0) > 0 then
		log(
			ngx and ngx.NOTICE,
			string.format("checked %d feed(s), imported %d post(s)", checked, imported or 0)
		)
	end
	return imported or 0
end

--- ngx.timer callback. Ignores the `premature` (worker-shutdown) tick and never
-- lets an error escape the timer.
function M.tick(premature)
	if premature then
		return
	end
	local ok, err = pcall(M.run_once)
	if not ok then
		log(ngx and ngx.ERR, "tick error: " .. tostring(err))
	end
end

--- Register the recurring timer. Idempotent per worker; a no-op unless running
-- under OpenResty with the scheduler enabled in config.
-- @treturn boolean whether a timer was registered
function M.start()
	if started then
		return false
	end
	if not (ngx and ngx.timer and ngx.timer.every) then
		return false
	end
	local opts = M.config()
	if not opts.enabled then
		return false
	end

	local ok, err = ngx.timer.every(opts.interval, M.tick)
	if not ok then
		log(ngx.ERR, "failed to register timer: " .. tostring(err))
		return false
	end
	started = true
	log(
		ngx.NOTICE,
		string.format("started (every %ds, base %ds)", opts.interval, opts.base_interval)
	)
	return true
end

return M

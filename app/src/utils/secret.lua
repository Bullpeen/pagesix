--- Session/CSRF signing secret resolution.
-- @module utils.secret
--
-- Lapis HMACs session cookies and CSRF tokens with `config.secret`. A missing
-- secret does not degrade gracefully: `openssl.hmac` raises ("string expected,
-- got nil") the first time anything is signed, so a deploy with the variable
-- unset boots clean and then 500s on effectively every request. Resolve it at
-- config load instead, and refuse to start when the environment being started
-- has no secret to sign with.
--
-- Two names are accepted because the config blocks historically disagreed:
-- development read `SESSION_SECRET`, production read `LAPIS_SECRET`. Either
-- works in either environment now; `SESSION_SECRET` is the documented one.

local M = {}

M.VARS = { "SESSION_SECRET", "LAPIS_SECRET" }

M.MISSING_MESSAGE = table.concat({
	"No session secret set for LAPIS_ENV=%s.",
	"Lapis signs session cookies and CSRF tokens with it, so the app cannot serve",
	"a single request without one. Set SESSION_SECRET (LAPIS_SECRET is accepted as",
	"the older name) to a long random value, e.g. `openssl rand -hex 32`.",
}, " ")

--- Resolve the secret for one `config(...)` block.
--
-- `config.lua` evaluates *every* environment's block on every boot, so a block
-- for an environment that is not being started must not raise -- only the
-- active one has to be satisfiable.
--
-- @tparam string env environment this config block describes, e.g. "production"
-- @tparam string active environment actually being started (`LAPIS_ENV`)
-- @tparam[opt] table opts `fallback` (string, used when nothing is set) and
--   `getenv` (function, injectable for tests; defaults to `os.getenv`)
-- @treturn string|nil the secret, or nil for an inactive block with no fallback
-- @raise when `env` is the active environment and no secret is available
function M.resolve(env, active, opts)
	opts = opts or {}
	local getenv = opts.getenv or os.getenv
	for _, var in ipairs(M.VARS) do
		local value = getenv(var)
		if value and value ~= "" then
			return value
		end
	end
	if opts.fallback then
		return opts.fallback
	end
	if env == active then
		error(string.format(M.MISSING_MESSAGE, tostring(env)), 0)
	end
	return nil
end

--- The environment being started. `lapis server` / `lapis migrate` set
-- LAPIS_ENV; it defaults to development exactly as Lapis itself does.
-- @treturn string
function M.active_env(getenv)
	getenv = getenv or os.getenv
	local env = getenv("LAPIS_ENV")
	if env == nil or env == "" then
		return "development"
	end
	return env
end

return M

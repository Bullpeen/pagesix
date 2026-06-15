--- Simple per-user, per-table rate limiting for content creation (flood control).
-- @module utils.ratelimit

local db = require("lapis.db")

local Ratelimit = {}

--- Has `user_id` created at least `limit` rows in `table_name` within the last
-- `window` seconds? `table_name` is a trusted constant ("posts"/"comments");
-- user_id and the cutoff are bound parameters. created_at is UTC
-- "YYYY-MM-DD HH:MM:SS" text, which sorts lexically, so a string cutoff works.
-- @tparam string table_name
-- @tparam number user_id
-- @tparam number limit
-- @tparam number window seconds
-- @treturn boolean
function Ratelimit.exceeded(table_name, user_id, limit, window)
	if not user_id then
		return false
	end
	local cutoff = os.date("!%Y-%m-%d %H:%M:%S", os.time() - window)
	local row = db.select(
		"COUNT(*) AS c FROM " .. table_name .. " WHERE user_id = ? AND created_at >= ?",
		user_id,
		cutoff
	)
	return tonumber(row[1].c) >= limit
end

return Ratelimit

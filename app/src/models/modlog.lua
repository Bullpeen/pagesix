--- Moderation log model
-- @module models.modlog

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Modlog = Model:extend("modlog", {
	timestamp = true,
})

--- A subreddit's moderation actions, newest first, with the acting moderator's
-- name and (when the action targeted a post) the post title for a permalink.
-- @tparam number sub_id
-- @tparam[opt=100] number limit
-- @treturn table array of modlog rows
function Modlog:for_subreddit(sub_id, limit)
	return db.select([[
		m.id, m.action, m.reason, m.created_at, m.post_id,
			u.user_name AS mod_name,
			p.title AS post_title
		FROM modlog m
		INNER JOIN users u ON m.mod_id = u.id
		LEFT JOIN posts p ON m.post_id = p.id
		WHERE m.sub_id = ]] .. tonumber(sub_id) .. [[
		ORDER BY m.created_at DESC, m.id DESC
		LIMIT ]] .. (tonumber(limit) or 100))
end

return Modlog

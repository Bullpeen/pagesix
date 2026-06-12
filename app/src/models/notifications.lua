--- Reply notifications (inbox)
-- @module models.notifications

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Notifications = Model:extend("notifications", {
	timestamp = true,
	relations = {
		{ "comment", belongs_to = "Comments" },
		{ "user", belongs_to = "Users" },
	},
})

--- Record a reply notification. No-op if there's no recipient.
function Notifications:notify(recipient_id, comment_id, kind)
	if not recipient_id then
		return
	end
	self:create({ user_id = recipient_id, comment_id = comment_id, kind = kind })
end

function Notifications:unread_count(user_id)
	return self:count("user_id = ? and seen = 0", user_id)
end

--- A user's notifications, newest first, with the reply comment + its context.
function Notifications:for_user(user_id)
	local rows = db.select([[
		n.id, n.kind, n.seen, n.created_at,
			c.id AS comment_id, c.body, c.post_id, c.parent_comment_id,
			u.user_name AS author,
			p.title AS post_title,
			s.name AS subreddit
		FROM notifications n
		INNER JOIN comments c ON n.comment_id = c.id
		INNER JOIN users u ON c.user_id = u.id
		INNER JOIN posts p ON c.post_id = p.id
		INNER JOIN forum s ON p.sub_id = s.id
		WHERE n.user_id = ]] .. tonumber(user_id) .. [[
		ORDER BY n.created_at DESC
		LIMIT 50]])

	for _, n in ipairs(rows) do
		n.permalink = "/r/" .. n.subreddit .. "/comments/" .. n.post_id .. "/_/" .. n.comment_id
	end

	return rows
end

--- Mark all of a user's notifications seen.
function Notifications:mark_read(user_id)
	db.update("notifications", { seen = 1 }, { user_id = user_id, seen = 0 })
end

return Notifications

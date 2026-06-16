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

--- Record a "mention" notification pointing at the comment OR post it occurred
-- in (pass whichever applies; the other is nil). No-op without a recipient.
function Notifications:notify_mention(recipient_id, comment_id, post_id)
	if not recipient_id then
		return
	end
	self:create({
		user_id = recipient_id,
		comment_id = comment_id,
		post_id = post_id,
		kind = "mention",
	})
end

function Notifications:unread_count(user_id)
	return self:count("user_id = ? and seen = 0", user_id)
end

--- A user's notifications, newest first. Each row points at a comment (replies
-- and comment-mentions) or a post (post-body mentions); the query LEFT JOINs
-- both sides so all kinds resolve. `author` is whoever wrote the comment/post,
-- `body` is the comment text (nil for a post mention), and `permalink` links to
-- the comment or the post.
function Notifications:for_user(user_id)
	local rows = db.select([[
		n.id, n.kind, n.seen, n.created_at, n.comment_id, n.post_id,
			c.body, c.parent_comment_id, c.post_id AS comment_post_id,
			cu.user_name AS comment_author,
			pu.user_name AS post_author,
			COALESCE(cp.title, dp.title) AS post_title,
			COALESCE(cs.name, ds.name) AS subreddit
		FROM notifications n
		LEFT JOIN comments c ON n.comment_id = c.id
		LEFT JOIN users cu ON c.user_id = cu.id
		LEFT JOIN posts cp ON c.post_id = cp.id
		LEFT JOIN forum cs ON cp.sub_id = cs.id
		LEFT JOIN posts dp ON n.post_id = dp.id
		LEFT JOIN users pu ON dp.user_id = pu.id
		LEFT JOIN forum ds ON dp.sub_id = ds.id
		WHERE n.user_id = ]] .. tonumber(user_id) .. [[
		ORDER BY n.created_at DESC
		LIMIT 50]])

	for _, n in ipairs(rows) do
		n.author = n.comment_author or n.post_author
		if n.comment_id and n.subreddit and n.comment_post_id then
			n.permalink = "/r/"
				.. n.subreddit
				.. "/comments/"
				.. n.comment_post_id
				.. "/_/"
				.. n.comment_id
		elseif n.post_id and n.subreddit then
			n.permalink = "/r/" .. n.subreddit .. "/comments/" .. n.post_id
		else
			n.permalink = "#"
		end
	end

	return rows
end

--- Mark all of a user's notifications seen.
function Notifications:mark_read(user_id)
	db.update("notifications", { seen = 1 }, { user_id = user_id, seen = 0 })
end

return Notifications

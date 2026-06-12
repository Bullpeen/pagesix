--- Subscriptions model
-- @module models.subscriptions

local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local Subscriptions = Model:extend("subscriptions", {
	timestamp = true,
	relations = {
		-- Subreddits live in the `forum` table (model `Forum`); there is no
		-- `Subreddits` model. belongs_to keys off subscriptions.subreddit_id.
		{ "subreddit", belongs_to = "Forum" },
		{ "user", belongs_to = "Users" },
	},
})

function Subscriptions:is_subscribed(user_id, subreddit_id)
	return self:find({ user_id = user_id, subreddit_id = subreddit_id }) ~= nil
end

--- Subscribe if not subscribed, otherwise unsubscribe.
-- @treturn boolean true if now subscribed, false if removed
function Subscriptions:toggle(user_id, subreddit_id)
	local existing = self:find({ user_id = user_id, subreddit_id = subreddit_id })
	if existing then
		existing:delete()
		return false
	end
	self:create({ user_id = user_id, subreddit_id = subreddit_id })
	return true
end

--- Forum rows a user is subscribed to (for the header nav and /subscribed).
function Subscriptions:subscribed_forums(user_id)
	return db.select([[
		f.id, f.name, f.description,
			(SELECT COUNT(*) FROM subscriptions x WHERE x.subreddit_id = f.id) AS subscribers
		FROM subscriptions s
		INNER JOIN forum f ON s.subreddit_id = f.id
		WHERE s.user_id = ]] .. tonumber(user_id) .. [[
		ORDER BY f.name]])
end

return Subscriptions

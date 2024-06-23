--- Subscriptions model
-- @module models.subscriptions


local Model = require("lapis.db.model").Model
local Subscriptions = Model:extend("subscriptions", {
	relations = {
		{ "subreddit", belongs_to = "Subreddits" },
		{ "user", belongs_to = "Users" },
	},
})

print("RUNNING MODELS.Subscriptions")

--- Subscribe to a subreddit
-- @tparam string subreddit_id
-- @treturn boolean success
function Subscriptions:subscribe(subreddit_id, user_id)
	return Subscriptions:create({
		subreddit_id = subreddit_id,
		user_id = user_id
	})
end

function Subscriptions:unsubscribe(subreddit_id, user_id)
	-- local user_id = Users:find()
	local sub = Subscriptions:find({
		subreddit_id = subreddit_id,
		user_id = user_id,
	})
	return Subscriptions:delete(sub)
end

function Subscriptions:get_subscribed(user_id)
	return Subscriptions:select("where user_id=?", user_id)
end

return Subscriptions

--- Subscriptions model
-- @module models.subscriptions

local Model = require("lapis.db.model").Model
local Subscriptions = Model:extend("subscriptions", {
	timestamp = true,
	relations = {
		{ "subreddit", belongs_to = "Subreddits" },
		{ "user", belongs_to = "Users" },
	},
})

--- Subscribe to a subreddit
-- @tparam string subreddit_id
-- @treturn boolean success
-- function Subscriptions:subscribe(subreddit_id, user_id)
-- 	return Subscriptions:create({
-- 		subreddit_id = subreddit_id,
-- 		user_id = user_id
-- 	})
-- end

-- function Subscriptions:unsubscribe(subreddit_id, user_id)
-- 	return Subscriptions:delete({
-- 		subreddit_id = subreddit_id,
-- 		user_id = user_id,
-- 	})
-- end

return Subscriptions

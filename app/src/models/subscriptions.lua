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

return Subscriptions

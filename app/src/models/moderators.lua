--- Moderators join table (user moderates subreddit)
-- @module models.moderators

local Model = require("lapis.db.model").Model

return Model:extend("moderators", {
	timestamp = true,
	relations = {
		{ "subreddit", belongs_to = "Forum" },
		{ "user", belongs_to = "Users" },
	},
})

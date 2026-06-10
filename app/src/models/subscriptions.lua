--- Subscriptions model
-- @module models.subscriptions

local Model = require("lapis.db.model").Model

local Subscriptions = Model:extend("subscriptions", {
	timestamp = true,
	relations = {
		-- Subreddits live in the `forum` table (model `Forum`); there is no
		-- `Subreddits` model. belongs_to keys off subscriptions.subreddit_id.
		{ "subreddit", belongs_to = "Forum" },
		{ "user", belongs_to = "Users" },
	},
})

return Subscriptions

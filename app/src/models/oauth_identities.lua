--- External OAuth provider identities linked to local users.
-- @module models.oauth_identities

local Model = require("lapis.db.model").Model

return Model:extend("oauth_identities", {
	timestamp = true,
	relations = {
		{ "user", belongs_to = "Users" },
	},
})

--- post <-> tag join rows.
-- @module models.post_tags

local Model = require("lapis.db.model").Model

return Model:extend("post_tags", {
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "tag", belongs_to = "Tags" },
	},
})

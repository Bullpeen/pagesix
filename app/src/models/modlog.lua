--- Moderation log model
-- @module models.modlog

local Model = require("lapis.db.model").Model

return Model:extend("modlog", {
	timestamp = true,
})

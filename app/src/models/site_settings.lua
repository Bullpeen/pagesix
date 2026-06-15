--- Runtime key/value site settings, editable from the Admin Control Panel.
-- @module models.site_settings

local Model = require("lapis.db.model").Model

local SiteSettings = Model:extend("site_settings", {
	timestamp = true,
})

--- The value stored under `key`, or `default` if it is unset.
-- @tparam string key
-- @param default returned when the key has no row (or a null value)
function SiteSettings:get(key, default)
	local row = self:find({ key = key })
	if row and row.value ~= nil then
		return row.value
	end
	return default
end

--- Set `key` to `value` (upsert). Returns the row.
-- @tparam string key
-- @tparam string value
function SiteSettings:set(key, value)
	local row = self:find({ key = key })
	if row then
		row:update({ value = value })
		return row
	end
	return self:create({ key = key, value = value })
end

--- All settings, ordered by key.
function SiteSettings:all()
	return self:select("ORDER BY key ASC")
end

return SiteSettings

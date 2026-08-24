--- Stamp a stable external id on rows at creation.
-- @module utils.public_id
--
-- Every publicly addressable row carries an opaque `public_id` (migration
-- `[109]`), which the JSON API exposes as a Thing's `uuid` so callers never
-- depend on the autoincrement primary key.
--
-- `[109]` backfilled the rows that existed then, but nothing minted an id for
-- rows created *after* it -- they stayed NULL until something serialized them,
-- at which point `api_serialize.ensure_public_id` re-read the column and minted
-- one. That is a SELECT (plus an UPDATE) per row, on the API's hottest path.
--
-- Minting at insert keeps the column populated, so the serializer's lazy path
-- only ever handles genuinely legacy rows.

local uuid = require("src.utils.uuid")

local M = {}

-- Tables confirmed to have the column. Migration `[109]` adds it, but earlier
-- migrations already create rows (`[10]` seeds a user), so minting has to be a
-- no-op until the column exists. Once seen, the answer can only stay true --
-- nothing drops the column -- so it is cached and the PRAGMA stops running.
local confirmed = {}

local function has_public_id(table_name)
	if confirmed[table_name] then
		return true
	end
	local db = require("lapis.db")
	-- `table_name` is the model's own name, never request input.
	for _, column in ipairs(db.query("PRAGMA table_info(" .. table_name .. ")") or {}) do
		if column.name == "public_id" then
			confirmed[table_name] = true
			return true
		end
	end
	return false
end

--- Wrap a model's `create` so new rows arrive with a `public_id`.
-- An explicitly supplied id is left alone.
-- @tparam table model the Lapis model to patch
function M.mint_on_create(model)
	local base_create = model.create
	model.create = function(self, values, ...)
		if
			type(values) == "table"
			and not values.public_id
			and has_public_id(self:table_name())
		then
			values.public_id = uuid.generate()
		end
		return base_create(self, values, ...)
	end
end

return M

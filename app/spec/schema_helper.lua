-- Runs the schema-creating migrations (everything before the seed-data steps)
-- so specs get a fresh schema without the heavy seed/RSS migrations.
local migrations = require("migrations")
local db = require("lapis.db")

return function()
	-- Enforce foreign keys in tests (set on the connection, outside a txn).
	db.query("PRAGMA foreign_keys = ON")
	for _, k in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 17, 18, 19, 21, 100, 101, 102 }) do
		if migrations[k] then
			migrations[k]()
		end
	end
end

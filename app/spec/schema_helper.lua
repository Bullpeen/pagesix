-- Runs the schema-creating migrations (everything before the seed-data steps)
-- so specs get a fresh schema without the heavy seed/RSS migrations.
local migrations = require("migrations")

return function()
	for _, k in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }) do
		if migrations[k] then
			migrations[k]()
		end
	end
end

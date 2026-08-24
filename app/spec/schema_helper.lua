-- Runs the schema-creating migrations (everything before the heavy seed/RSS
-- steps) so specs get a fresh schema quickly.
--
-- This now includes [10], which seeds the synthetic `anonymous_coward` account,
-- so the test schema matches what production actually has. That account takes
-- `users.id = 1`, which is why specs must never assume "the row I just created
-- is id 1" -- create fixtures in `setup` and reference `fixture.id` instead.
local migrations = require("migrations")
local db = require("lapis.db")

return function()
	-- Enforce foreign keys in tests (set on the connection, outside a txn).
	db.query("PRAGMA foreign_keys = ON")
	for _, k in ipairs({
		1,
		2,
		3,
		4,
		5,
		6,
		7,
		8,
		9,
		10, -- the synthetic `anonymous_coward` account, as production has it
		11,
		12,
		17,
		18,
		19,
		21,
		100,
		101,
		102,
		103,
		104,
		105,
		106,
		107,
		108,
		109,
		110,
		111, -- idempotent backfill of [10]; a no-op here, but keeps this list honest
		112, -- partial unique indexes on votes
		113, -- drops the superseded moderators / user_profiles tables
	}) do
		if migrations[k] then
			migrations[k]()
		end
	end
end

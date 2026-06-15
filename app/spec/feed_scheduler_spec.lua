--- Unit specs for the in-process feed scheduler's worker-coordination logic
--- (lock + run_once dispatch). No ngx, no DB: feed_import.refresh_all is stubbed
--- and a fake shared dict stands in for ngx.shared.

local feed_scheduler = require("src.utils.feed_scheduler")
local feed_import = require("src.utils.feed_import")

-- Minimal ngx.shared dict: :add is create-if-absent (the real atomic lock).
local function fake_dict()
	local store = {}
	return {
		add = function(_, k, v)
			if store[k] ~= nil then
				return false, "exists"
			end
			store[k] = v
			return true
		end,
		delete = function(_, k)
			store[k] = nil
		end,
	}
end

describe("feed_scheduler", function()
	local orig_refresh_all = feed_import.refresh_all

	after_each(function()
		feed_import.refresh_all = orig_refresh_all
		_G.ngx = nil
	end)

	it("runs the importer when the lock is free and returns the import count", function()
		local got_interval
		feed_import.refresh_all = function(base_interval)
			got_interval = base_interval
			return 3, 2 -- imported, checked
		end
		local imported =
			feed_scheduler.run_once({ base_interval = 123, dict = "feed_scheduler", lock_ttl = 10 })
		assert.same(3, imported)
		assert.same(123, got_interval)
	end)

	it("lets exactly one worker run when they contend for the lock", function()
		_G.ngx = { shared = { feed_scheduler = fake_dict() } }
		local runs = 0
		feed_import.refresh_all = function()
			runs = runs + 1
			return 0, 0
		end
		local opts = { base_interval = 900, dict = "feed_scheduler", lock_ttl = 600 }

		-- The lock is released at the end of each pass, so sequential ticks both
		-- run; to prove mutual exclusion we hold the lock from the outside first.
		assert.is_true(feed_scheduler.acquire_lock(opts))
		assert.is_nil(feed_scheduler.run_once(opts)) -- lock held -> skipped
		assert.same(0, runs)

		feed_scheduler.release_lock(opts)
		assert.same(0, feed_scheduler.run_once(opts)) -- now free -> runs
		assert.same(1, runs)
	end)

	it("acquire_lock is always true without a shared dict (single worker/dev)", function()
		_G.ngx = nil
		assert.is_true(feed_scheduler.acquire_lock({ dict = "feed_scheduler", lock_ttl = 10 }))
	end)

	it("swallows importer errors so a bad tick never crashes the worker", function()
		feed_import.refresh_all = function()
			error("boom")
		end
		assert.is_nil(feed_scheduler.run_once({ base_interval = 900, dict = "x", lock_ttl = 10 }))
	end)

	it("config falls back to the documented defaults", function()
		local cfg = feed_scheduler.config()
		assert.same(900, cfg.interval)
		assert.same(900, cfg.base_interval)
		assert.same(600, cfg.lock_ttl)
		assert.same("feed_scheduler", cfg.dict)
	end)
end)

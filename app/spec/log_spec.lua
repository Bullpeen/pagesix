--- utils.log spec
-- Exercises both back ends: the ngx.log path used under OpenResty and the
-- stderr fallback used by the CLI/migrations/this suite.

describe("utils.log", function()
	local log = require("src.utils.log")

	-- Swap io.stderr for a recorder (the real one is a userdata handle whose
	-- methods cannot be monkeypatched under LuaJIT).
	local function capture_stderr(fn)
		local written = {}
		local real = io.stderr
		io.stderr = { -- luacheck: ignore 122
			write = function(_, line)
				written[#written + 1] = line
			end,
		}
		local ok, err = pcall(fn)
		io.stderr = real -- luacheck: ignore 122
		assert.is_true(ok, tostring(err))
		return written
	end

	it("writes to stderr when ngx is absent", function()
		local written = capture_stderr(function()
			log.tag("demo").error("boom")
		end)
		assert.same({ "ERROR [demo] boom\n" }, written)
	end)

	it("routes through ngx.log with the matching severity when available", function()
		local calls = {}
		_G.ngx = {
			ERR = 3,
			WARN = 4,
			NOTICE = 5,
			log = function(level, line)
				calls[#calls + 1] = { level, line }
			end,
		}
		local logger = log.tag("scheduler")
		local ok, err = pcall(function()
			logger.error("bad")
			logger.warn("meh")
			logger.notice("fyi")
		end)
		_G.ngx = nil
		assert.is_true(ok, tostring(err))

		assert.same({ 3, "[scheduler] bad" }, calls[1])
		assert.same({ 4, "[scheduler] meh" }, calls[2])
		assert.same({ 5, "[scheduler] fyi" }, calls[3])
	end)

	it("stringifies non-string messages instead of erroring", function()
		local written = capture_stderr(function()
			log.tag("demo").warn(nil)
		end)
		assert.same({ "WARN [demo] nil\n" }, written)
	end)
end)

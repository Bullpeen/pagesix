--- Operational endpoints: a JSON /health probe and a Prometheus /metrics
--- exporter. Both are public and layout-free (machine-readable).
-- @module src.ops
--
-- Registered after the homepage `/(:sort)` catch-all; that's fine because Lapis
-- routes literal segments ahead of named captures, so `/health` and `/metrics`
-- win over `:sort` (same as `/search`, `/about`, ...).

local function ops(app)
	-- Liveness/readiness probe. 200 + {status:"ok"} when the DB answers a trivial
	-- query; 503 + {status:"error"} otherwise, so an orchestrator can act on it.
	app:get("/health", function()
		local config = require("lapis.config").get()
		local ok = pcall(function()
			return require("lapis.db").select("1 AS one")
		end)
		return {
			status = ok and 200 or 503,
			json = {
				status = ok and "ok" or "error",
				db = ok and "ok" or "error",
				service = config.name,
				time = os.time(),
			},
		}
	end)

	-- Prometheus scrape target (text exposition v0.0.4).
	app:get("/metrics", function()
		return {
			content_type = "text/plain; version=0.0.4",
			layout = false,
			require("src.utils.metrics").render(),
		}
	end)

	return app
end

return ops

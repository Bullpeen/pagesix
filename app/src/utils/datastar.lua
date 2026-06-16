--- Minimal Datastar server helpers: detect a Datastar request and emit an SSE
--- element patch so actions can respond async (no full page reload) while the
--- plain <form> POST stays the no-JS fallback.
-- @module utils.datastar

local Datastar = {}

--- True when the request came from the Datastar client (it sets this header).
-- @tparam table self the Lapis request
-- @treturn boolean
function Datastar.is_request(self)
	return self.req.headers["datastar-request"] == "true"
end

--- A `text/event-stream` response that patches element(s) into the DOM. Datastar
-- matches by `id` and morphs in place (default mode). `html` is the full outer
-- HTML of the element(s); keep it on a single line (SSE is newline-delimited).
-- @tparam table self the Lapis request
-- @tparam string html
-- @treturn table a Lapis write spec
function Datastar.patch_elements(self, html)
	self.res.headers["Content-Type"] = "text/event-stream"
	self.res.headers["Cache-Control"] = "no-cache"
	return {
		layout = false,
		"event: datastar-patch-elements\ndata: elements " .. html .. "\n\n",
	}
end

return Datastar

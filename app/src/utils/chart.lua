--- Server-rendered inline SVG charts (no client JS).
-- @module utils.chart
--
-- The front-end is deliberately classless + JS-free (Datastar only), so the
-- admin/mod dashboards draw their graphs as inline SVG built here on the server.
-- Two shapes: `vbars` for a time series (vertical bars) and `hbars` for a
-- labelled leaderboard (horizontal bars). Both return an SVG string ready to
-- drop into a template; values are clamped/escaped so untrusted labels are safe.

local xml = require("src.utils.xml")

local M = {}

-- Round to 2 decimals so the emitted SVG stays compact and deterministic.
local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

local function max_value(values)
	local m = 0
	for _, v in ipairs(values) do
		v = tonumber(v) or 0
		if v > m then
			m = v
		end
	end
	return m
end

local function svg_open(w, h, title)
	return ('<svg viewBox="0 0 %d %d" role="img" aria-label="%s" data-chart>'):format(
		w,
		h,
		xml.escape(title or "chart")
	)
end

--- Vertical bar chart for a time series (e.g. posts/day).
-- @tparam table values numeric array, oldest first
-- @tparam[opt] table opts { title, width=600, height=120, caption }
-- @treturn string SVG markup
function M.vbars(values, opts)
	opts = opts or {}
	local w, h = opts.width or 600, opts.height or 120
	local n = #values
	if n == 0 then
		return svg_open(w, h, opts.title) .. "</svg>"
	end
	local max = max_value(values)
	-- A flat (all-zero) series still draws a baseline rather than dividing by 0.
	local scale = max > 0 and (h - 4) / max or 0
	local bw = w / n

	local parts = { svg_open(w, h, opts.title) }
	for i, v in ipairs(values) do
		v = tonumber(v) or 0
		local bh = r2(v * scale)
		local x = r2((i - 1) * bw)
		local y = r2(h - bh)
		parts[#parts + 1] = ('<rect x="%s" y="%s" width="%s" height="%s"><title>%s</title></rect>'):format(
			x,
			y,
			r2(bw * 0.9),
			bh,
			xml.escape(tostring(v))
		)
	end
	parts[#parts + 1] = "</svg>"
	return table.concat(parts)
end

--- Horizontal labelled bar chart for a leaderboard (e.g. top subreddits).
-- @tparam table items array of { label = string, value = number }, biggest first
-- @tparam[opt] table opts { title, width=600, row_height=22 }
-- @treturn string SVG markup
function M.hbars(items, opts)
	opts = opts or {}
	local w = opts.width or 600
	local rh = opts.row_height or 22
	local n = #items
	local h = math.max(rh, n * rh)
	if n == 0 then
		return svg_open(w, rh, opts.title) .. "</svg>"
	end

	local values = {}
	for i, it in ipairs(items) do
		values[i] = tonumber(it.value) or 0
	end
	local max = max_value(values)
	-- Leave room on the left for labels; bars fill the rest proportionally.
	local label_w = r2(w * 0.35)
	local bar_area = w - label_w
	local scale = max > 0 and bar_area / max or 0

	local parts = { svg_open(w, h, opts.title) }
	for i, it in ipairs(items) do
		local v = values[i]
		local y = r2((i - 1) * rh)
		local bw = r2(v * scale)
		local label = xml.escape(it.label)
		parts[#parts + 1] = ('<text x="0" y="%s">%s</text>'):format(r2(y + rh * 0.7), label)
		parts[#parts + 1] = ('<rect x="%s" y="%s" width="%s" height="%s"><title>%s: %s</title></rect>'):format(
			label_w,
			r2(y + rh * 0.15),
			bw,
			r2(rh * 0.7),
			label,
			v
		)
		parts[#parts + 1] = ('<text x="%s" y="%s">%s</text>'):format(
			r2(label_w + bw + 4),
			r2(y + rh * 0.7),
			v
		)
	end
	parts[#parts + 1] = "</svg>"
	return table.concat(parts)
end

return M

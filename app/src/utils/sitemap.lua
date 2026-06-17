--- Build a sitemaps.org urlset XML document.
-- @module utils.sitemap

local esc = require("src.utils.xml").escape

--- @tparam table urls array of { loc = "https://...", lastmod = "2024-01-02" }
--   (lastmod is optional; only the date part, if present, is emitted)
-- @treturn string the sitemap XML
return function(urls)
	local parts = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
	}

	for _, u in ipairs(urls or {}) do
		-- Sitemaps want a W3C date; our timestamps are "YYYY-MM-DD HH:MM:SS",
		-- so keep just the date portion when a lastmod is given.
		local lastmod = u.lastmod and tostring(u.lastmod):match("^%d%d%d%d%-%d%d%-%d%d")
		parts[#parts + 1] = table.concat({
			"<url>",
			"<loc>" .. esc(u.loc) .. "</loc>",
			lastmod and ("<lastmod>" .. lastmod .. "</lastmod>") or "",
			"</url>",
		})
	end

	parts[#parts + 1] = "</urlset>"
	return table.concat(parts)
end

--- Build an RSS 2.0 feed document from a channel + items.
-- @module utils.rss

local esc = require("src.utils.xml").escape

--- @tparam table channel { title, link, description, items = { {title, link, guid, author, description}, ... } }
-- @treturn string the RSS XML
return function(channel)
	local parts = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<rss version="2.0"><channel>',
		"<title>" .. esc(channel.title) .. "</title>",
		"<link>" .. esc(channel.link) .. "</link>",
		"<description>" .. esc(channel.description) .. "</description>",
	}

	for _, item in ipairs(channel.items or {}) do
		parts[#parts + 1] = table.concat({
			"<item>",
			"<title>" .. esc(item.title) .. "</title>",
			"<link>" .. esc(item.link) .. "</link>",
			'<guid isPermaLink="false">' .. esc(item.guid) .. "</guid>",
			item.author and ("<author>" .. esc(item.author) .. "</author>") or "",
			"<description>" .. esc(item.description) .. "</description>",
			"</item>",
		})
	end

	parts[#parts + 1] = "</channel></rss>"
	return table.concat(parts)
end

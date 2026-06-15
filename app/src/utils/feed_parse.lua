--- Minimal RSS 2.0 / Atom feed parser -> entry list.
-- @module utils.feed_parse
--
-- Uses luaexpat (lxp.lom) only, so it has no network side effects and is
-- unit-testable against fixture XML. Returns a flat list of
-- { title, link, guid } for each <item> (RSS) or <entry> (Atom).

local lom = require("lxp.lom")

local function trim(s)
	return s and (s:gsub("^%s+", ""):gsub("%s+$", "")) or s
end

-- Strip any namespace prefix and lowercase: "atom:link" -> "link".
local function localname(tag)
	return tag and (tag:gsub("^.-:", "")):lower() or nil
end

-- First direct child element with the given (namespace-stripped) tag name.
local function child(node, name)
	for _, c in ipairs(node) do
		if type(c) == "table" and localname(c.tag) == name then
			return c
		end
	end
end

-- Concatenated text content of an element.
local function text(node)
	if type(node) ~= "table" then
		return nil
	end
	local out = {}
	for _, c in ipairs(node) do
		if type(c) == "string" then
			out[#out + 1] = c
		end
	end
	return trim(table.concat(out))
end

-- All descendant elements named `name`, without descending into matches.
local function collect(node, name, acc)
	acc = acc or {}
	if type(node) ~= "table" then
		return acc
	end
	for _, c in ipairs(node) do
		if type(c) == "table" then
			if localname(c.tag) == name then
				acc[#acc + 1] = c
			else
				collect(c, name, acc)
			end
		end
	end
	return acc
end

-- An entry's link: RSS <link>text</link>, or Atom <link href="..."> preferring
-- rel="alternate"/no rel over other relations (enclosure, self, ...).
local function entry_link(item)
	local fallback
	for _, c in ipairs(item) do
		if type(c) == "table" and localname(c.tag) == "link" then
			local t = text(c)
			if t and t ~= "" then
				return t -- RSS-style text link
			end
			local href = c.attr and c.attr.href
			if href then
				local rel = c.attr.rel
				if not rel or rel == "alternate" then
					return href
				end
				fallback = fallback or href
			end
		end
	end
	return fallback
end

--- @tparam string xml the raw feed document
-- @treturn table array of { title, link, guid }
return function(xml)
	if not xml or xml == "" then
		return {}
	end
	local ok, tree = pcall(lom.parse, xml)
	if not ok or type(tree) ~= "table" then
		return {}
	end

	local items = collect(tree, "item") -- RSS
	if #items == 0 then
		items = collect(tree, "entry") -- Atom
	end

	local entries = {}
	for _, item in ipairs(items) do
		local link = entry_link(item)
		if link and link ~= "" then
			local title = text(child(item, "title")) or "(untitled)"
			local guid = text(child(item, "guid")) or text(child(item, "id")) or link
			entries[#entries + 1] = {
				title = title:sub(1, 300), -- posts.title constraint caps at 300
				link = link,
				guid = guid,
			}
		end
	end
	return entries
end

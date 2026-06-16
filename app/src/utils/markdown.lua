--- Render Markdown to sanitized HTML.
-- @module utils.markdown

local ok_md, markdown = pcall(require, "markdown")
local ok_san, web_sanitize = pcall(require, "web_sanitize")

local function escape(text)
	return (text:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

--- @tparam string text raw, user-supplied markdown
-- @treturn string HTML safe to emit with a raw (`<%- %>`) etlua tag
return function(text)
	if not text or text == "" then
		return ""
	end
	if ok_md and ok_san then
		-- Turn @mentions into Markdown profile links first, then render and
		-- sanitize so any embedded raw HTML can't inject scripts/styles/etc.
		text = require("src.utils.mentions").linkify(text)
		return web_sanitize.sanitize_html(markdown(text))
	end
	-- Fallback if the optional rocks aren't present: escape and keep newlines.
	return (escape(text):gsub("\n", "<br>\n"))
end

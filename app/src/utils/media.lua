--- Tiny helpers for classifying a post's link as an image (for thumbnails).
-- @module utils.media

local M = {}

local IMAGE_EXT = {
	jpg = true,
	jpeg = true,
	png = true,
	gif = true,
	webp = true,
	bmp = true,
	svg = true,
	avif = true,
}

--- Is this URL a direct image link (by file extension)?
-- @tparam string url
-- @treturn boolean
function M.is_image(url)
	if type(url) ~= "string" or url == "" then
		return false
	end
	-- Drop any query string / fragment before looking at the extension.
	local path = url:lower():gsub("[?#].*$", "")
	local ext = path:match("%.([%a%d]+)$")
	return ext ~= nil and IMAGE_EXT[ext] == true
end

--- The thumbnail URL for a post link: the image itself for image links, else
--- nil (non-image links get no thumbnail).
-- @tparam string url
-- @treturn string|nil
function M.thumbnail_for(url)
	return M.is_image(url) and url or nil
end

return M

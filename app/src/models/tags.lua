--- Tags: a flat tag vocabulary plus helpers to read/replace a post's tags.
-- @module models.tags

local db = require("lapis.db")
local Model = require("lapis.db.model").Model

local Tags = Model:extend("tags", {
	timestamp = true,
})

-- At most this many tags per post; longer tags are dropped.
Tags.MAX_PER_POST = 5
Tags.MAX_LEN = 32

--- Parse a free-text tags field ("foo, bar baz") into a deduped, slugified list,
-- capped at MAX_PER_POST. Slugs are lowercase [a-z0-9-]. Pure (no DB).
-- @tparam string raw
-- @treturn table array of slug strings
function Tags.normalize(raw)
	local seen, out = {}, {}
	for token in tostring(raw or ""):gmatch("[^,%s]+") do
		local slug =
			token:lower():gsub("[^%w%-]+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
		if slug ~= "" and #slug <= Tags.MAX_LEN and not seen[slug] then
			seen[slug] = true
			out[#out + 1] = slug
			if #out >= Tags.MAX_PER_POST then
				break
			end
		end
	end
	return out
end

--- Replace a post's tags with those parsed from `raw` (find-or-create each tag).
-- @tparam number post_id
-- @tparam string raw the free-text tags field
function Tags:set_for_post(post_id, raw)
	post_id = tonumber(post_id)
	if not post_id then
		return
	end
	local PostTags = require("src.models.post_tags")
	db.delete("post_tags", { post_id = post_id })
	for _, name in ipairs(Tags.normalize(raw)) do
		local tag = self:find({ name = name }) or self:create({ name = name })
		PostTags:create({ post_id = post_id, tag_id = tag.id })
	end
end

--- The tag names attached to a post, alphabetical.
-- @tparam number post_id
-- @treturn table array of tag-name strings
function Tags:for_post(post_id)
	local rows = db.select(
		[[
		t.name FROM tags t
			INNER JOIN post_tags pt ON pt.tag_id = t.id
			WHERE pt.post_id = ? ORDER BY t.name]],
		tonumber(post_id)
	)
	local names = {}
	for _, r in ipairs(rows) do
		names[#names + 1] = r.name
	end
	return names
end

return Tags

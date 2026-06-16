--- @mention parsing: extract @usernames from text, resolve them to users, and
--- linkify them for Markdown rendering.
-- @module utils.mentions

local Mentions = {}

-- A username token: starts with a letter/digit, then letters/digits/_/-.
-- `%f[@%w]@` is a frontier so the @ only counts at a word boundary -- not when
-- preceded by a word character (so "bob@example" is an email, not a mention).
local MENTION_PAT = "%f[@%w]@(%w[%w_%-]*)"

-- Drop fenced and inline code so @names inside code aren't treated as mentions.
local function strip_code(text)
	text = text:gsub("```.-```", " ")
	text = text:gsub("`[^`]*`", " ")
	return text
end

--- Distinct usernames mentioned in `text` (original case of first occurrence).
-- @tparam string text
-- @treturn table array of username strings
function Mentions.extract(text)
	local seen, out = {}, {}
	for name in strip_code(tostring(text or "")):gmatch(MENTION_PAT) do
		local key = name:lower()
		if not seen[key] then
			seen[key] = true
			out[#out + 1] = name
		end
	end
	return out
end

--- Resolve the mentions in `text` to existing user rows, skipping
-- `exclude_user_id` (so you never notify yourself).
-- @tparam string text
-- @tparam[opt] number exclude_user_id
-- @treturn table array of user rows
function Mentions.resolve(text, exclude_user_id)
	local Users = require("models.users")
	local users = {}
	for _, name in ipairs(Mentions.extract(text)) do
		local user = Users:find({ user_name = name })
		if user and tonumber(user.id) ~= tonumber(exclude_user_id) then
			users[#users + 1] = user
		end
	end
	return users
end

--- Rewrite @mentions to Markdown profile links so the renderer turns them into
-- anchors. Pure text transform; runs before Markdown rendering.
-- @tparam string text
-- @treturn string
function Mentions.linkify(text)
	if not text or text == "" then
		return text
	end
	return (text:gsub(MENTION_PAT, "[@%1](/user/%1)"))
end

return Mentions

--- Hidden posts model
-- @module models.hidden_posts

local Model = require("lapis.db.model").Model

local HiddenPosts = Model:extend("hidden_posts", {
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "user", belongs_to = "Users" },
	},
})

function HiddenPosts:is_hidden(user_id, post_id)
	return self:find({ user_id = user_id, post_id = post_id }) ~= nil
end

--- Hide if not hidden, otherwise unhide. @treturn boolean now hidden?
function HiddenPosts:toggle(user_id, post_id)
	local existing = self:find({ user_id = user_id, post_id = post_id })
	if existing then
		existing:delete()
		return false
	end
	self:create({ user_id = user_id, post_id = post_id })
	return true
end

return HiddenPosts

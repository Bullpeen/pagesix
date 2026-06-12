--- Saved posts model
-- @module models.saved_posts

local Model = require("lapis.db.model").Model

local SavedPosts = Model:extend("saved_posts", {
	timestamp = true,
	relations = {
		{ "post", belongs_to = "Posts" },
		{ "user", belongs_to = "Users" },
	},
})

function SavedPosts:is_saved(user_id, post_id)
	return self:find({ user_id = user_id, post_id = post_id }) ~= nil
end

--- Save if not saved, otherwise unsave. @treturn boolean now saved?
function SavedPosts:toggle(user_id, post_id)
	local existing = self:find({ user_id = user_id, post_id = post_id })
	if existing then
		existing:delete()
		return false
	end
	self:create({ user_id = user_id, post_id = post_id })
	return true
end

return SavedPosts

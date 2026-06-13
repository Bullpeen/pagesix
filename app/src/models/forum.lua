--- Forum model
-- @module models.forum

local model = require("lapis.db.model")
local Model = model.Model

local Forum = Model:extend("forum", {
	timestamp = true,

	-- url_params = function(self, req, ...)
	-- 	return "/"
	-- end,

	constraints = {
		--- Apply constraints when updating/inserting a Subreddit row, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		name = function(self, value)
			if not value or value == "" then
				return "Subreddit name is required"
			end

			-- A SET keyed by name (the previous array, indexed by string, never
			-- matched, so reserved names slipped through).
			local reserved = {
				admin = true,
				all = true,
				controversial = true,
				mods = true,
				new = true,
				pagesix = true,
				popular = true,
				random = true,
				subscribed = true,
				unsubscribed = true,
			}
			if reserved[value] then
				return "Subreddit name is reserved"
			end

			-- valid length (2-64]
			if #value >= 64 then
				return "Subreddits must be less than 64 characters"
			end
			if #value < 2 then
				return "Subreddits must be at least 2 characters"
			end
		end,
	},

	relations = {
		{ "creator", belongs_to = "Users" },
		{ "moderators", has_many = "Users" },
		{ "subscribers", has_many = "Subscriptions" },
		{ "posts", has_many = "Posts" },
	},
})

--- Whether a user may moderate this subreddit: its creator, or a member of the
-- moderators join table.
-- @tparam number user_id
-- @tparam table forum a forum row
-- @treturn boolean
function Forum:can_moderate(user_id, forum)
	if not forum or not user_id then
		return false
	end
	-- The creator is always a moderator.
	if tonumber(forum.creator_id) == tonumber(user_id) then
		return true
	end
	-- Otherwise check the moderators join table (replaces the legacy
	-- forum.moderator_ids CSV).
	local Moderators = require("src.models.moderators")
	return Moderators:find({ subreddit_id = forum.id, user_id = user_id }) ~= nil
end

--- Add a user as a moderator of a subreddit (idempotent).
function Forum:add_moderator(subreddit_id, user_id)
	local Moderators = require("src.models.moderators")
	if not Moderators:find({ subreddit_id = subreddit_id, user_id = user_id }) then
		Moderators:create({ subreddit_id = subreddit_id, user_id = user_id })
	end
end

return Forum

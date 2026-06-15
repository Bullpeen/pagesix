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

--- Whether a user may moderate this subreddit.
-- Back-compat shim over the privilege matrix (src/utils/privileges.lua): gates
-- the generic mod-tools UI. "remove" is the canonical moderation power held by
-- both owners and moderators. New code should call Privileges.can(...) with the
-- specific privilege it needs instead.
-- @tparam number user_id
-- @tparam table forum a forum row
-- @treturn boolean
function Forum:can_moderate(user_id, forum)
	local Privileges = require("src.utils.privileges")
	return Privileges.can(user_id, forum, "remove")
end

--- Make a user the owner of a subreddit (idempotent).
function Forum:add_owner(subreddit_id, user_id)
	require("src.models.roles"):assign(subreddit_id, user_id, "owner")
end

--- Add a user as a moderator of a subreddit (idempotent).
function Forum:add_moderator(subreddit_id, user_id)
	require("src.models.roles"):assign(subreddit_id, user_id, "moderator")
end

return Forum

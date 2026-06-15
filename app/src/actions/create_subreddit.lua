--- Create subreddit action
-- @module action.create_subreddit

local Users = require("models.users")
local Forum = require("src.models.forum")

return {
	-- POST /subreddit/create  (form: name, description)
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		-- name is UNIQUE; a duplicate insert would throw, so check first.
		if self.params.name and Forum:find({ name = self.params.name }) then
			self.errors = { "Subreddit already exists" }
			return { redirect_to = self:url_for("subreddits") }
		end

		-- The Forum model's `name` constraint validates length/reserved names;
		-- create() returns nil + the message on failure.
		local sub, err = Forum:create({
			name = self.params.name,
			description = self.params.description,
			creator_id = user.id,
		})
		if not sub then
			self.errors = { err }
			return { redirect_to = self:url_for("subreddits") }
		end

		-- The creator owns their subreddit (full privileges; see utils.privileges).
		Forum:add_owner(sub.id, user.id)

		return { redirect_to = self:url_for("subreddit", { subreddit = sub.name }) }
	end,
}

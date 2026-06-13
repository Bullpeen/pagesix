--- Crosspost: re-share an existing post into another subreddit, linked back to
--- the original via crosspost_parent_id.
-- @module action.crosspost

local Users = require("models.users")
local Posts = require("src.models.posts")
local Forum = require("src.models.forum")

return {
	-- POST /post/:post_id/crosspost   (form: subreddit)
	POST = function(self)
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		local original = Posts:find(tonumber(self.params.post_id))
		if not original or tonumber(original.deleted) == 1 then
			return { redirect_to = self:url_for("homepage") }
		end

		-- Crosspost the source post (not a crosspost-of-a-crosspost): point at
		-- the original root so the chain stays one level deep.
		local source_id = tonumber(original.crosspost_parent_id) or original.id

		local sub = self.params.subreddit and Forum:find({ name = self.params.subreddit })
		if not sub then
			self.errors = { "Unknown subreddit: " .. tostring(self.params.subreddit) }
			return { redirect_to = self:url_for(original) }
		end

		local post = Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = original.title,
			url = original.url,
			body = original.body,
			is_self = original.is_self,
			thumbnail = original.thumbnail,
			crosspost_parent_id = source_id,
		})

		if not post then
			return { redirect_to = self:url_for(original) }
		end
		return { redirect_to = self:url_for(post) }
	end,
}

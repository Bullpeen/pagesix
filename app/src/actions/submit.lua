--- Submit action
-- @module action.submit

local Posts = require("src.models.posts")
local Forum = require("src.models.forum")
local Users = require("models.users")
local Spam = require("src.utils.spam")
local media = require("src.utils.media")
local markdown = require("src.utils.markdown")
local Queue = require("src.utils.queue")
local Ratelimit = require("src.utils.ratelimit")

-- Flood control: at most this many posts per user per window (seconds).
local RATE_LIMIT, RATE_WINDOW = 10, 600

return {
	before = function(self) end,

	GET = function(self)
		return { render = "submit" }
	end,

	-- Form fields (see views/fragments/form_submit.etlua): url, title, subreddit.
	POST = function(self)
		-- /submit is behind auth (src/auth.lua), so a user must be signed in.
		local user = self.session.current_user
			and Users:find({ user_name = self.session.current_user })
		if not user then
			return self:write({ redirect_to = self:url_for("login") })
		end

		-- Preview: render the self-post body as Markdown and re-show the form
		-- (with the entered values) without creating anything.
		if self.params.preview then
			self.preview_html = markdown(self.params.body or "")
			return { render = "submit" }
		end

		-- Subreddits live in the `forum` table, keyed by name.
		local sub = self.params.subreddit and Forum:find({ name = self.params.subreddit })
		if not sub then
			self.errors = { "Unknown subreddit: " .. tostring(self.params.subreddit) }
			return { render = "submit" }
		end

		-- A post is either a link (url) or a self/text post (body). If a body
		-- is given and no url, it's a self post.
		local url = self.params.url
		local body = self.params.body
		if (url == nil or url == "") and (body == nil or body == "") then
			self.errors = { "Provide a URL or some text" }
			return { render = "submit" }
		end
		local is_self = (url == nil or url == "") and body ~= nil and body ~= ""

		-- Bayesian spam check on the prose (title + self-post body; the URL is
		-- not tokenized as text). Fails open if untrained / too short.
		if Spam.is_spam((self.params.title or "") .. " " .. (body or "")) then
			self.errors = { "Your post looks like spam and was not submitted." }
			return { render = "submit" }
		end

		-- Flood control before we write anything.
		if Ratelimit.exceeded("posts", user.id, RATE_LIMIT, RATE_WINDOW) then
			self.errors = { "You're posting too fast. Try again in a few minutes." }
			return { render = "submit" }
		end

		-- Brand-new users' posts are held for a moderator (approved = 0).
		local held = Queue.should_hold(user, sub)

		local link = (url ~= "") and url or nil
		local post, err = Posts:create({
			user_id = user.id,
			sub_id = sub.id,
			title = self.params.title,
			url = link,
			body = (body ~= "") and body or nil,
			is_self = is_self and 1 or 0,
			thumbnail = media.thumbnail_for(link),
			approved = held and 0 or 1,
			is_question = self.params.is_question and 1 or 0,
		})

		if not post then
			self.errors = { err }
			return { render = "submit" }
		end

		-- Attach any tags from the form (parsed/slugified by the model).
		require("src.models.tags"):set_for_post(post.id, self.params.tags)

		-- @mention notifications for a visible self-post body (held posts notify
		-- nobody until approved, mirroring the comment path).
		if not held and body and body ~= "" then
			local Mentions = require("src.utils.mentions")
			local Notifications = require("models.notifications")
			for _, mentioned in ipairs(Mentions.resolve(body, user.id)) do
				Notifications:notify_mention(mentioned.id, nil, post.id)
			end
		end

		-- A held post is hidden from listings and its own page, so send the
		-- author to the subreddit (where a future flash can explain the wait)
		-- rather than to a page that would just bounce them home.
		if held then
			return { redirect_to = self:url_for("subreddit", { subreddit = sub.name }) }
		end

		return { redirect_to = self:url_for(post) }
	end,
}

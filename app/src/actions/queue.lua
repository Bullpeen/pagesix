--- Moderator approval queue: review posts/comments held from new users.
--- GET lists what's pending; POST approves or rejects a single item. Gated by
--- the RBAC `approve` privilege (moderators, owners, and site admins).
-- @module action.queue

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Comments = require("models.comments")
local Modlog = require("src.models.modlog")
local Privileges = require("src.utils.privileges")

-- modlog.action codes for queue decisions (reason text carries the detail).
local ACTION_APPROVE, ACTION_REJECT = 6, 7

local function review(self, model, id, op, modlog_keys)
	local row = model:find(id)
	if not row then
		return
	end
	if op == "approve" then
		row:update({ approved = 1 })
	elseif op == "reject" then
		-- Approve out of the queue but soft-delete so it stays hidden.
		row:update({ approved = 1, deleted = 1 })
	else
		return
	end
	local entry = {
		mod_id = self.current_user.id,
		sub_id = self.forum.id,
		action = op == "approve" and ACTION_APPROVE or ACTION_REJECT,
		reason = (op == "approve" and "approved " or "rejected ")
			.. modlog_keys.label
			.. " (queue)",
	}
	entry[modlog_keys.fk] = row.id
	Modlog:create(entry)
end

return {
	before = function(self)
		local sub = Forum:find({ name = self.params.subreddit })
		if not sub then
			return self:write({ redirect_to = self:url_for("homepage") })
		end
		self.forum = sub
		self.subreddit = sub.name

		if not self.current_user then
			return self:write({ redirect_to = self:url_for("login") })
		end
		if not Privileges.can(self.current_user.id, sub, "approve") then
			return self:write({
				status = 403,
				layout = false,
				"Forbidden — the approval queue is for this community's moderators.",
			})
		end
	end,

	GET = function(self)
		self.pending_posts = Posts:pending_for_sub(self.forum.id)
		self.pending_comments = Comments:pending_for_sub(self.forum.id)
		return { render = "queue" }
	end,

	-- POST /r/:subreddit/queue  (form: kind = post|comment, id, op = approve|reject)
	POST = function(self)
		local id = tonumber(self.params.id)
		local op = self.params.op
		if id then
			if self.params.kind == "post" then
				local post = Posts:find(id)
				-- Only act on items that belong to this subreddit's queue.
				if post and tonumber(post.sub_id) == tonumber(self.forum.id) then
					review(self, Posts, id, op, { fk = "post_id", label = "post" })
				end
			elseif self.params.kind == "comment" then
				local comment = Comments:find(id)
				local post = comment and Posts:find(comment.post_id)
				if post and tonumber(post.sub_id) == tonumber(self.forum.id) then
					review(self, Comments, id, op, { fk = "comment_id", label = "comment" })
				end
			end
		end
		return { redirect_to = self:url_for("queue", { subreddit = self.forum.name }) }
	end,
}

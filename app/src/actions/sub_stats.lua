--- Per-subreddit statistics + graphs for that community's moderators.
--- Gated by the RBAC `approve` privilege (moderators/owners/site admins),
--- mirroring the approval queue.
-- @module action.sub_stats

local Forum = require("src.models.forum")
local Privileges = require("src.utils.privileges")
local Stats = require("src.utils.stats")
local chart = require("src.utils.chart")

local function series(points, key)
	local v = {}
	for i, p in ipairs(points) do
		v[i] = p[key]
	end
	return v
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
				"Forbidden — stats are for this community's moderators.",
			})
		end

		local days = 30
		local activity = Stats.for_sub(sub.id, days)
		self.days = days
		self.sub_totals = Stats.sub_totals(sub.id)
		self.range = {
			from = activity[1] and activity[1].day,
			to = activity[#activity] and activity[#activity].day,
		}

		self.charts = {
			posts = chart.vbars(series(activity, "posts"), { title = "Posts per day" }),
			comments = chart.vbars(series(activity, "comments"), { title = "Comments per day" }),
		}

		local items = {}
		for _, c in ipairs(Stats.top_contributors(sub.id, 10)) do
			items[#items + 1] = { label = c.name, value = tonumber(c.posts) or 0 }
		end
		self.charts.contributors = chart.hbars(items, { title = "Top contributors by posts" })
	end,

	GET = function(self)
		return { render = "sub_stats" }
	end,
}

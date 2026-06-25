--- Spec for utils/stats: site/sub totals, the v_daily_activity-backed series,
--- and the leaderboards.

local use_test_env = require("lapis.spec").use_test_env

describe("stats", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Comments = require("models.comments")
	local Votes = require("src.models.votes")
	local Stats = require("src.utils.stats")

	local u, f

	setup(function()
		require("spec.schema_helper")()
		u = Users:create({ user_name = "statguy", user_pass = "password", user_email = "s@e.com" })
		f = Forum:create({ name = "statsub", creator_id = u.id, description = "stats" })
		for i = 1, 3 do
			local p = Posts:create({
				user_id = u.id,
				sub_id = f.id,
				title = "post " .. i,
				url = "https://s.example/" .. i,
			})
			if i == 1 then
				Comments:create({ post_id = p.id, user_id = u.id, body = "c1" })
				Comments:create({ post_id = p.id, user_id = u.id, body = "c2" })
				Votes:set(u.id, p.id, nil, 1)
			end
		end
	end)

	-- Sum a numeric column across an activity series.
	local function total(series, key)
		local s = 0
		for _, p in ipairs(series) do
			s = s + (p[key] or 0)
		end
		return s
	end

	it("reports site totals", function()
		local t = Stats.totals()
		assert.same(3, t.posts)
		assert.same(2, t.comments)
		assert.same(1, t.votes)
		assert.truthy(t.users >= 1)
		assert.truthy(t.subreddits >= 1)
	end)

	it("returns a zero-padded daily series from the view", function()
		local series = Stats.activity(7)
		assert.same(7, #series)
		-- Everything was created within the window, so the sums match the totals.
		assert.same(3, total(series, "posts"))
		assert.same(2, total(series, "comments"))
		assert.truthy(total(series, "signups") >= 1)
	end)

	it("clamps the day span", function()
		assert.same(1, #Stats.activity(0))
		assert.same(365, #Stats.activity(99999))
	end)

	it("ranks top subreddits by post count", function()
		local tops = Stats.top_subreddits(10)
		local found
		for _, s in ipairs(tops) do
			if s.name == "statsub" then
				found = s
			end
		end
		assert.truthy(found)
		assert.same(3, tonumber(found.posts))
	end)

	it("reports per-subreddit totals + activity", function()
		local t = Stats.sub_totals(f.id)
		assert.same(3, t.posts)
		assert.same(2, t.comments)
		assert.same(0, t.subscribers)

		local series = Stats.for_sub(f.id, 7)
		assert.same(7, #series)
		assert.same(3, total(series, "posts"))
		assert.same(2, total(series, "comments"))
	end)

	it("ranks top contributors", function()
		local top = Stats.top_contributors(f.id, 5)
		assert.same("statguy", top[1].name)
		assert.same(3, tonumber(top[1].posts))
	end)
end)

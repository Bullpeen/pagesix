--- Domain action
-- @module action.domain

local db = require("lapis.db")

return {
	before = function(self)
		self.domain = self.params.domain

		-- Check if domain is nil or empty
		if self.domain == nil or self.domain == "" then
			print("Domain is unknown: " .. self.domain)
			-- return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- check if domain has a period anywhere in it
		if not string.find(self.domain, "%.") then
			print("Domain is invalid: " .. self.domain)
			-- return self:write({ redirect_to = self:url_for("homepage") })
		end

		-- search all _posts tables for url like %domain%
		-- TODO subquery to return a table like
		-- {
		-- 		post_id: { title, url, domain, user_id, created_at, is_self, body, upvotes, downvotes, num_comments },
		-- 		post_id: { ... },
		-- }

		-- TODO improve query
		local p, _ = db.select("score, url, title, permalink FROM 'v_frontpage_hot'")

		local posts = {}
		for _, post in pairs(p) do
			local d = post.url:match("[%w%.]*%.(%w+%.%w+)")
			-- print("URL IS " .. post.url)
			-- print("D IS " .. d)
			post.domain=d
			if self.domain == d then
				table.insert(posts, post)
			end
		end
		self.posts = posts
	end,

	GET = function(self)
		return { render = "domain" }
	end,
}

--- XML sitemap: the homepage, every subreddit, and recent posts.
-- @module action.sitemap

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local sitemap = require("src.utils.sitemap")

-- Cap the post section so the document stays a sane size on a large DB.
local MAX_POSTS = 500

return {
	-- GET /sitemap.xml
	GET = function(self)
		local urls = { { loc = self:build_url("/") } }

		for _, sub in ipairs(Forum:select("where deleted_at is null order by name") or {}) do
			urls[#urls + 1] = { loc = self:build_url("/r/" .. sub.name) }
		end

		local posts = Posts:get_listing()
		for i = 1, math.min(#posts, MAX_POSTS) do
			local p = posts[i]
			urls[#urls + 1] = {
				loc = self:build_url(p.permalink),
				lastmod = p.updated_at or p.created_at,
			}
		end

		return {
			content_type = "application/xml",
			layout = false,
			sitemap(urls),
		}
	end,
}

--- RSS output feed for the frontpage or a subreddit
-- @module action.feed

local Posts = require("src.models.posts")
local Forum = require("src.models.forum")
local Sort = require("src.utils.sort")
local rss = require("src.utils.rss")

return {
	-- GET /.rss            (frontpage)
	-- GET /r/:subreddit/.rss
	GET = function(self)
		local title, link, posts

		if self.params.subreddit then
			local sub = Forum:find({ name = self.params.subreddit })
			if not sub then
				return { status = 404, layout = false, "Not found" }
			end
			title = "/r/" .. sub.name
			link = "/r/" .. sub.name
			posts = Sort:sort(Posts:get_listing(sub.id), "hot")
		else
			title = "Page Six"
			link = "/"
			posts = Sort:sort(Posts:get_listing(), "hot")
		end

		local items = {}
		for i = 1, math.min(#posts, 25) do
			local p = posts[i]
			items[i] = {
				title = p.title,
				link = p.url and p.url ~= "" and p.url or p.permalink,
				guid = p.permalink,
				author = p.author,
				description = p.body or "",
			}
		end

		return {
			content_type = "application/rss+xml",
			layout = false,
			rss({ title = title, link = link, description = title .. " — posts", items = items }),
		}
	end,
}

--- Misc utils
-- @module utils.misc

local Misc = {}
Misc.__index = Misc

math.randomseed(os.clock() * 100000000000)

local io = require("io")

function Misc:File_exists(path)
	local file = io.open(path, "rb") -- r read mode and b binary mode
	if not file then
		return nil
	end
end

function Misc:read_file(path)
	local file = io.open(path, "rb") -- r read mode and b binary mode
	if not file then
		return nil
	end

	local content = file:read("*a") -- *a or *all reads the whole file
	file:close()

	return content
end

-- function Misc:Validate_email(input)
-- 	if input:match(".+@.+%..+") then
-- 		return true
-- 	else
-- 		return false, "%s is not a valid email"
-- 	end
-- end

function Misc:rss_feed(subreddit, url)
	local http = require("socket.http")
	local feedparser = require("feedparser")
	local Forum = require("src.models.forum")
	local Posts = require("src.models.posts")
	local Users = require("src.models.users")
	local users = Users:select()
	if #users == 0 then
		return
	end

	-- Resolve the real subreddit id by name; object_types is a fixed enum that
	-- need not correspond to forum.id.
	local sub = Forum:find({ name = subreddit })
	if not sub then
		print("rss_feed: unknown subreddit " .. tostring(subreddit))
		return
	end

	local response, status = http.request(url)
	if type(status) == "number" and status >= 200 and status < 400 and response then
		local parsed = feedparser.parse(response)
		if parsed == nil then
			return nil, "parse error"
		end

		for _, item in ipairs(parsed.entries) do
			if item.link == nil then
				item.link = "#"
			end

			local s, e = Posts:create({
				title = item.title,
				url = item.link,
				sub_id = sub.id,
				user_id = users[math.random(#users)].id,
			})
			if not s then
				print("error creating post from feed: " .. tostring(e))
			end
		end
	else
		print("! RSS request failed for " .. tostring(url) .. ". Status: " .. tostring(status))
	end
end

function Misc:generate_posts(subreddit_id, n)
	local Lorem = require("src.utils.lorem")

	local Posts = require("src.models.posts")

	local Users = require("src.models.users")
	-- Need the rows (a random user is picked below), so :select() is required
	-- here -- :count() can't return the ids.
	local users = Users:select()

	if #users == 0 then
		return
	end

	-- print("!!! generating " .. n .. " posts")
	for i = 1, n do
		local p_tbl = {
			title = Lorem:sentence(),
			url = "http://" .. Lorem:word() .. ".com/" .. i,
			sub_id = subreddit_id,
			user_id = users[math.random(#users)].id,
		}

		local s, e = Posts:create(p_tbl)
		if not s then
			print("error creating post: " .. tostring(e))
			break
		end
	end
end

function Misc:generate_comments(post_id, n)
	local Comments = require("src.models.comments")
	local Users = require("src.models.users")
	local Lorem = require("src.utils.lorem")

	local users = Users:select()
	if #users == 0 then
		return
	end

	for _ = 1, n do
		local tbl = {
			post_id = post_id,
			user_id = users[math.random(#users)].id,
			body = Lorem:paragraph(),
		}

		-- set a variable 25% chance of creating a top-level comment
		-- local coin = math.random(1, 4)
		-- if coin > 3 then
		-- 	tbl.parent_comment_id = math.random(1, i)
		-- end

		local s, e = Comments:create(tbl)
		if not s then
			print("error creating comment: " .. tostring(e))
			break
		end
	end
end

function Misc:generate_post_votes(post_id, n)
	local Users = require("src.models.users")
	local Votes = require("src.models.votes")

	local users = Users:select()
	if #users == 0 then
		return
	end

	-- One vote per (user, post): cap at the number of users and pick distinct
	-- voters so we never violate UNIQUE(user_id, post_id, comment_id).
	n = math.min(n, #users)
	local voted = {}
	local created = 0
	while created < n do
		local uid = users[math.random(#users)].id
		if not voted[uid] then
			voted[uid] = true
			Votes:create({
				user_id = uid,
				post_id = post_id,
				upvote = math.random(0, 1),
			})
			created = created + 1
		end
	end
end

function Misc:generate_comment_votes(post_id, n)
	local Comments = require("src.models.comments")
	local Votes = require("src.models.votes")

	local Users = require("src.models.users")
	local users = Users:select()
	if #users == 0 then
		return
	end

	-- get comments from post_id
	local comments = Comments:select("where post_id = ?", post_id)

	for _, c in ipairs(comments) do
		for _ = 1, n do
			local uid = users[math.random(#users)].id
			local exists = Votes:find({
				user_id = uid,
				post_id = post_id,
				comment_id = c.id,
			})
			if not exists then
				Votes:create({
					user_id = uid,
					post_id = post_id,
					comment_id = c.id,
					upvote = math.random(0, 1),
				})
			end
		end
	end
end

return Misc

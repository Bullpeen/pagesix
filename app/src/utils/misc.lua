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

function Misc:Generate_password()
	local upperCase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	local lowerCase = "abcdefghijklmnopqrstuvwxyz"
	local numbers = "0123456789"
	local symbols = "!@#$%&*+-,./<=>?^"

	local characterSet = upperCase .. lowerCase .. numbers .. symbols

	local keyLength = 32
	local output = ""

	for _ = 1, keyLength do
		local rand = math.random(#characterSet)
		output = output .. string.sub(characterSet, rand, rand)
	end
	return output
end

function Misc:Validate_email(input)
	if input:match(".+@.+%..+") then
		return true
	else
		return false, "%s is not a valid email"
	end
end

function Misc:rss_feed(subreddit_id, url)
	local subreddit = subreddit_id or 1
	local http = require("socket.http")
	local feedparser = require("feedparser")
	local Posts = require("src.models.posts")
	local Users = require("src.models.users")
	local users = Users:select()

	local feed_url = url

	local response, status, _ = http.request(feed_url)
	if status == 200 then
		local parsed = feedparser.parse(response)

		-- Print out feed details.
		print("> Title   ", parsed.feed.title)
		print("> Author  ", parsed.feed.author)
		print("> ID      ", parsed.feed.id)
		print("> Entries ", #parsed.entries)

		for _, item in ipairs(parsed.entries) do
			print("Title   ", item.title)
			print("Link    ", item.link)

			local p_tbl = {
				title = item.title,
				url = item.link,
				permalink = string.match(tostring(math.random()), "%.(%d+)"), -- TODO generate useful permalink?
				sub_id = subreddit,
				user_id = math.random(#users),
			}
			local s, e = Posts:create(p_tbl)
			if not s then
				print("error creating " .. item.title)
				print(e)
				break
			end
		end
	else
		print("! Request failed. Status:", status)
	end
end

function Misc:generate_posts(subreddit_id, n)
	local Lorem = require("src.utils.lorem")

	local Posts = require("src.models.posts")

	local Users = require("src.models.users")
	local users = Users:select()

	print("!!! generating " .. n .. " posts")
	for i = 1, n do
		local permalink = string.match(tostring(math.random()), "%.(%d+)") -- TODO make permalink meaningful

		local p_tbl = {
			title = Lorem:sentence(),
			url = "http://" .. Lorem:word() .. ".com/" .. i,
			permalink = permalink,
			sub_id = subreddit_id,
			user_id = math.random(#users),
		}

		local s, e = Posts:create(p_tbl)
		if not s then
			print("error creating " .. s.title)
			print(e)
			break
		end
	end
end

function Misc:generate_comments(post_id, n)
	local Comments = require("src.models.comments")
	local Users = require("src.models.users")
	local Lorem = require("src.utils.lorem")

	local users = Users:select()

	for i = 1, n do
		local tbl = {
			post_id = post_id,
			user_id = math.random(#users),
			permalink = post_id .. "_" .. i, -- TODO fix md5?
			body = Lorem:paragraph(),
		}

		-- set a variable 25% chance of creating a top-level comment
		-- local coin = math.random(1, 4)
		-- if coin > 3 then
		-- 	tbl.parent_comment_id = math.random(1, i)
		-- end

		-- require 'pl.pretty'.dump(tbl)

		local s, e = Comments:create(tbl)
		if not s then
			print("error creating " .. s.body)
			print(e)
			break
		end
	end
end

function Misc:generate_post_votes(post_id, n)
	-- local db = require("lapis.db")
	local Users = require("src.models.users")
	local Votes = require("src.models.votes")

	local users = Users:select()
	-- local posts = db.select("* FROM ?", "posts")

	for _=1, n do
		Votes:create({
			user_id = math.random(#users),
			post_id = post_id,
			upvote = math.random(0, 1),
		})
	end
end

function Misc:generate_comment_votes(post_id, n)
	local Comments = require("src.models.comments")
	local Votes = require("src.models.votes")

	local Users = require("src.models.users")
	local users = Users:select()

	-- get comments from post_id
	local comments = Comments:select("where post_id = ?", post_id)

	-- require 'pl.pretty'.dump(comments)

	for _, c in pairs(comments) do
		-- require 'pl.pretty'.dump(c)
		for i=1, n do
			Votes:create({
				user_id = math.random(#users - n) + i,
				post_id = post_id,
				comment_id = c.id,
				upvote = math.random(0, 1),
			})
		end
	end
end

return Misc

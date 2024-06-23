--- Migrations
-- @script migrations

local db = require("lapis.db")
local io = require("io")
local json = require("cjson")
local Lorem = require("src.utils.lorem")
-- local util = require("lapis.util")
local misc = require("src.utils.misc")

-- local Comments = require("src.models.comments")
-- local Votes = require("src.models.votes")
local Pagesix = require("src.models.pagesix")
local Posts = require("src.models.posts")
local Subreddits = require("src.models.subreddits")
local Users = require("src.models.users")

-- math.randomseed(os.clock() * 100000000000)

-- add each incremental migration whose key is the unix timestamp
return {
	-- create initial tables: Users, Subreddits
	[1] = function()
		Pagesix:bootstrap()
	end,

	-- create first User
	[2] = function()
		Users:create({
			user_name = "anonymous_coward",
			user_email = "anonymous@localhost",
			user_pass = "",
		})
	end,

	-- create initial subreddits
	[3] = function()
		-- TODO figure out utils module
		local data = {}
		local path = "/var/data/initial_subs.json"
		local file = io.open(path, "rb")

		if file then
			local content = file:read("*a") -- *a or *all reads the whole file
			file:close()
			data = json.decode(content)
			-- require 'pl.pretty'.dump(data)
			print("Read in " .. #data .. " subreddits from " .. path)
		end

		for _, sub in ipairs(data) do
			print("About to create new sub: " .. sub.name .. ".")
			local s, e = Subreddits:create({
				name = sub.name,
				description = sub.description or "",
				creator_id = sub.creator_id or 1,
			})
			if not s then
				print("error creating " .. s.name)
				print(e)
			end

			-- print("NAME IS " .. sub.name)
			-- local slug = util:slugify(sub.name)
			-- print("SLUG IN " .. slug)

			-- Hot sort subreddit
			db.query(
				[[
					CREATE VIEW IF NOT EXISTS ?
					AS
					SELECT COUNT(*) score,
						(SELECT COUNT(*) FROM 'comments' d WHERE d.post_id = a.id) num_comments,
						a.created_at age, a.title, a.url, a.permalink, a.over_18, a.locked,
						c.user_name author
					FROM 'posts' a
					INNER JOIN 'votes' b ON a.id = b.post_id
					INNER JOIN 'users' c ON b.user_id = c.id
					INNER JOIN 'comments' d ON a.id = d.post_id
					WHERE a.locked = 0
						AND b.comment_id IS NULL
						AND a.id = b.post_id
						AND b.upvote = 1
						AND a.sub_id = ?
						AND a.id = d.post_id
					GROUP BY a.id, b.post_id
					ORDER BY COUNT(*) DESC;
				]],
				"v_" .. s.id .. "_hot",
				s.id
			)

			-- New sort subreddit
			-- db.query(
			-- 	[[
			-- 		CREATE VIEW IF NOT EXISTS ?
			-- 		AS
			-- 		SELECT COUNT(*) score,
			-- 			(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id),
			-- 			a.created_at age, a.title, a.url, a.permalink, a.over_18, a.locked,
			-- 			c.user_name author
			-- 		FROM 'posts' a
			-- 		INNER JOIN 'votes' b ON a.id=b.post_id
			-- 		INNER JOIN 'users' c ON b.user_id = c.id
			-- 		INNER JOIN 'comments' d ON a.id = d.post_id
			-- 		WHERE a.locked = 0
			-- 			AND b.comment_id IS NULL
			-- 			AND a.id = b.post_id
			-- 			AND a.sub_id = ?
			-- 		GROUP BY a.id, b.post_id
			-- 		ORDER BY age, COUNT(*) DESC;
			-- 	]],
			-- 	"v_" .. s.id .. "_new",
			-- 	s.id
			-- )

			-- Top sort subreddit
			-- db.query(
			-- 	[[
			-- 		CREATE VIEW IF NOT EXISTS ?
			-- 		AS
			-- 		SELECT COUNT(*) score,
			-- 			(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id),
			-- 			a.created_at age, a.title, a.url, a.permalink, a.over_18, a.locked,
			-- 			c.user_name author
			-- 		FROM 'posts' a
			-- 		INNER JOIN 'votes' b ON a.id=b.post_id
			-- 		INNER JOIN 'users' c ON b.user_id = c.id
			-- 		INNER JOIN 'comments' d ON a.id = d.post_id
			-- 		WHERE a.locked = 0
			-- 			AND b.comment_id IS NULL
			-- 			AND a.id = b.post_id
			-- 			AND a.sub_id = ?
			-- 		GROUP BY a.id, b.post_id
			-- 		ORDER BY COUNT(*) DESC;
			-- 	]],
			-- 	"v_" .. s.id .. "_top",
			-- 	s.id
			-- )
		end

		-- Hot sort frontpage
		db.query(
			[[
					CREATE VIEW IF NOT EXISTS ?
					AS
					SELECT COUNT(*) score,
						(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id) num_comments,
						a.title, a.url, a.permalink, a.over_18, a.locked,
						c.user_name author
					FROM 'posts' a
					INNER JOIN 'votes' b ON a.id=b.post_id
					INNER JOIN 'users' c ON b.user_id = c.id
					INNER JOIN 'comments' d ON a.id = d.post_id
					WHERE a.locked = 0
						AND b.comment_id IS NULL
						AND b.upvote = 1
						AND a.id = b.post_id
					GROUP BY a.id, b.post_id
					ORDER BY COUNT(*) DESC;
			]],
			"v_frontpage_hot"
		)

		-- New sort frontpage
		-- db.query(
		-- 	[[
		-- 			CREATE VIEW IF NOT EXISTS ?
		-- 			AS
		-- 			SELECT COUNT(*) score,
		-- 				(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id) num_comments,
		-- 				a.created_at age, a.title, a.url, a.permalink, a.over_18, a.locked,
		-- 				c.user_name author
		-- 			FROM 'posts' a
		-- 			INNER JOIN 'votes' b ON a.id=b.post_id
		-- 			INNER JOIN 'users' c ON b.user_id = c.id
		-- 			WHERE a.locked = 0
		-- 				AND b.comment_id IS NULL
		-- 				AND a.id = b.post_id
		-- 			GROUP BY a.id, b.post_id
		-- 			ORDER BY age, COUNT(*) DESC;
		-- 	]],
		-- 	"v_frontpage_new"
		-- )

		-- Top sort frontpage
		-- db.query(
		-- 	[[
		-- 			CREATE VIEW IF NOT EXISTS ?
		-- 			AS
		-- 			SELECT COUNT(*) score,
		-- 				(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id) num_comments,
		-- 				a.created_at age, a.title, a.url, a.permalink, a.over_18, a.locked,
		-- 				c.user_name author
		-- 			FROM 'posts' a
		-- 			INNER JOIN 'votes' b ON a.id=b.post_id
		-- 			INNER JOIN 'users' c ON b.user_id = c.id
		-- 			WHERE a.locked = 0
		-- 				AND b.comment_id IS NULL
		-- 				AND a.id = b.post_id
		-- 			GROUP BY a.id, b.post_id
		-- 			ORDER BY COUNT(*) DESC;
		-- 	]],
		-- 	"v_frontpage_top"
		-- )
	end,

	-- create Users with random user_names
	[4] = function()
		for i = 1, 100 do
			local name = Lorem:word() .. "_" .. i
			local s, e = Users:create({
				user_name = name,
				user_email = name .. "@localhost",
				user_pass = "hunter2",
			})
			if not s then
				print("error creating " .. name)
				print(e)
				break
			end
		end
	end,

	-- loop through all Subreddits and create some Posts for each
	[5] = function()
		local subreddits = Subreddits:select()

		for sub in pairs(subreddits) do
			misc:generate_posts(sub, 5)
		end
	end,

	-- [66] = function()
	-- 	local feed_url = "https://www.reddit.com/r/politics.rss"
	-- 	misc:rss_feed(1, feed_url)
	-- end,

	-- cast Votes on posts in each subreddit
	[10] = function()
		local posts = Posts:select()

		for post in pairs(posts) do
			misc:generate_post_votes(post, 5)
		end
	end,

	-- create Comments on each post
	[20] = function()
		local posts = Posts:select()

		for post in pairs(posts) do
			misc:generate_comments(post, 5)
		end
	end,

	-- create 10 votes on each comment
	[30] = function()
		local posts = Posts:select()

		for post in pairs(posts) do
			misc:generate_comment_votes(post, 1)
		end
	end,

	-- classify text : https://github.com/leafo/lapis-bayes
	[1439944992] = require("lapis.bayes.schema").run_migrations,
}

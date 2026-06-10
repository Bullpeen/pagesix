--- Migrations
-- @script migrations

local db = require("lapis.db")
local io = require("io")
local json = require("cjson")
local Lorem = require("src.utils.lorem")
-- local util = require("lapis.util")
local misc = require("src.utils.misc")

local schema = require("lapis.db.schema")
local types = schema.types

local Forum = require("src.models.forum")
local Posts = require("src.models.posts")
local Subscriptions = require("src.models.subscriptions")
local Users = require("src.models.users")

math.randomseed(os.clock() * 100000000000)

local opts = {}
opts["strict"] = true
opts["if_not_exists"] = true

-- add each incremental migration whose key is the unix timestamp
return {
    [1] = function()
        -- PRAGMA journal_mode=WAL
        local pragma = {
            journal_mode="WAL",
            synchronous="NORMAL",
            temp_store="MEMORY",
            mmap_size=1000000000,
            page_size=32768,
        }

        for k, v in pairs(pragma) do
            db.query("PRAGMA " .. k .. "=" .. v)
        end

        -- db.query("PRAGMA journal_mode=WAL")
        -- db.query("PRAGMA synchronous=NORMAL")

        -- if (mode ~= "wal") then
        --     print ("Error setting WAL mode: " .. mode)
        --     os.exit()
        -- end
    end,

    -- create Users, User_Profiles & Subscriptions tables
    [2] = function()
        schema.create_table("users", {
            { "id",             types.integer({ unique = true, primary_key = true }) },
            { "user_name",      types.text({ unique = true }) },
            { "user_pass",      types.text },
            { "user_email",     types.text },

            { "created_at",     types.text },
            { "updated_at",     types.text },

            { "deleted_at",     types.text({ null = true }) },
            { "over_18",        types.integer({ default = false }) },
            { "verified_email", types.integer({ default = false }) },
        }, opts)

        schema.create_table("user_profiles", {
            { "id",          types.integer({ unique = true, primary_key = true }) },
            { "user_email",  types.text },
            { "description", types.text },

            { "created_at", types.text },
            { "updated_at", types.text },
            { "deleted_at", types.text({ null = true }) },

            "FOREIGN KEY(id) REFERENCES users(id)",
        }, opts)

        schema.create_index("users", "user_name", { unique = true })

        schema.create_table("subscriptions", {
            { "id",           types.integer({ unique = true, primary_key = true }) },
            { "user_id",      types.integer },
            { "subreddit_id", types.integer },

            { "created_at", types.text },
            { "updated_at", types.text },

            "FOREIGN KEY(user_id) REFERENCES users(id)",
            "FOREIGN KEY(subreddit_id) REFERENCES forum(id)",

            "UNIQUE(user_id, subreddit_id)",
        }, opts)

        schema.create_table("reserved_usernames", {
            { "id",         types.integer({ unique = true, primary_key = true }) },
            { "user_name",  types.text({ unique = true }) },

            { "created_at", types.text },
            { "updated_at", types.text },

        }, opts)
    end,

    -- create Forum table
    [3] = function()
        schema.create_table("forum", {
            { "id",            types.integer({ unique = true, primary_key = true }) },
            { "name",          types.text({ unique = true }) },

            { "created_at",    types.text },
            { "deleted_at",    types.text({ null = true }) },
            { "updated_at",    types.text },

            { "creator_id",    types.integer({ default = 1 }) }, -- TODO rename
            { "description",   types.text({ null = true }) },
            { "moderator_ids", types.text({ null = true }) },
            { "nsfw",          types.integer({ default = false }) },
            { "feeds",         types.text({ null = true }) },

            "FOREIGN KEY(creator_id) REFERENCES users(id)",
        }, opts)

        -- create_index("subreddits", "name", { unique = true })
    end,

    -- create Posts, Comments & Votes tables
    [4] = function()
        -- create subreddit's table containing Posts by Users
        schema.create_table("posts", {
            { "id",         types.integer({ unique = true, primary_key = true }) },
            { "user_id",    types.integer },
            { "sub_id",     types.integer },

            { "title",      types.text },
            { "url",        types.text },
            -- { "domain", types.TEXT, "GENERATED ALWAYS AS (url_host(url)) VIRTUAL"},
            { "created_at", types.text },
            { "updated_at", types.text },

            { "locked",     types.integer({ default = false }) },
            { "edited",     types.integer({ default = false }) },
            { "is_self",    types.integer({ default = false }) },
            { "over_18",    types.integer({ default = false }) },
            { "body",       types.text({ null = true }) },

            "FOREIGN KEY(sub_id) REFERENCES forum(id)",
            "FOREIGN KEY(user_id) REFERENCES users(id)",
        }, opts)

        -- create subreddit's table containing Comments by Users
        schema.create_table("comments", {
            { "id",                types.integer({ unique = true, primary_key = true }) },
            { "post_id",           types.integer },
            { "user_id",           types.integer },
            -- { "permalink", types.text({ unique = true }) },
            { "parent_comment_id", types.integer({ null = true }) },
            { "body",              types.text },

            { "created_at",        types.text },
            { "updated_at",        types.text },

            { "edited",            types.integer({ default = false }) },
            { "deleted",           types.integer({ default = false }) },
            { "is_submitter",      types.integer({ default = false }) },
            { "stickied",          types.integer({ default = false }) },

            "FOREIGN KEY(user_id) REFERENCES users(id)",
            "FOREIGN KEY(post_id) REFERENCES posts(id)",

            "UNIQUE(user_id, post_id, parent_comment_id)",
        }, opts)

        -- create each subreddit table containing Votes on Posts or Comments by Users
        schema.create_table("votes", {
            { "id",         types.integer({ unique = true, primary_key = true }) },
            { "user_id",    types.integer },
            { "post_id",    types.integer },
            { "comment_id", types.integer({ null = true }) },
            { "upvote",     types.integer({ default = true }) },

            { "created_at", types.text },
            { "updated_at", types.text },

            "FOREIGN KEY(user_id) REFERENCES users(id)",
            "FOREIGN KEY(post_id) REFERENCES posts(id)",
            "FOREIGN KEY(comment_id) REFERENCES comments(id)",

            "UNIQUE(user_id, post_id, comment_id)",
        }, opts)

        schema.create_table("modlog", {
            { "id",         types.integer({ unique = true, primary_key = true }) },
            { "mod_id",     types.text },
            { "user_id",    types.text({ null = true }) },
            { "sub_id",     types.text({ null = true }) }, -- TODO remove?
            { "post_id",    types.text({ null = true }) },
            { "comment_id", types.text({ null = true }) },
            { "action",     types.integer({ null = true }) },
            { "reason",     types.text },

            { "created_at", types.text },
            { "updated_at", types.text },

            "FOREIGN KEY(mod_id) REFERENCES users(id)", -- TODO
            "FOREIGN KEY(user_id) REFERENCES users(id)",
            "FOREIGN KEY(sub_id) REFERENCES forum(id)",
            "FOREIGN KEY(post_id) REFERENCES posts(id)",
            "FOREIGN KEY(comment_id) REFERENCES comments(id)",
        }, opts)

        db.query([[
				CREATE VIEW IF NOT EXISTS ?
				AS
				SELECT COUNT(*) subscribers,
					a.name, a.description, a.nsfw
				FROM 'forum' a
				INNER JOIN 'subscriptions' b ON a.id = b.subreddit_id
				WHERE a.id = b.subreddit_id
				GROUP BY a.id, b.subreddit_id
				ORDER BY COUNT(*) DESC;
			]],
            "v_forum")
    end,

    -- create first User
    [10] = function()
        Users:create({
            user_name = "anonymous_coward",
            user_email = "anonymous@localhost",
            user_pass = "",
        })
    end,

    -- create initial subreddits
    [13] = function()
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

            local feeds_str = ""
            if sub.feeds ~= nil then
                for _, feed_url in pairs(sub.feeds) do
                    feeds_str = feed_url .. "," .. feeds_str
                    print("sub " .. sub.name .. " has feed_url " .. feed_url)
                end

                -- sub.feeds =
                print(feeds_str)
            end

            local s, e = Forum:create({
                name = sub.name,
                description = sub.description or Lorem:sentence(),
                creator_id = sub.creator_id or 1,
                feeds = feeds_str
            })


            if not s then
                print("error creating " .. sub.name)
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
					SELECT
						(SELECT COUNT(*) upvotes FROM 'votes' b WHERE b.post_id = a.id AND b.comment_id IS NULL AND b.upvote = 1) upvotes,
						(SELECT COUNT(*) upvotes FROM 'votes' b WHERE b.post_id = a.id AND b.comment_id IS NULL AND b.upvote = 0) downvotes,
						(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id) num_comments,
						a.title, a.url, a.over_18, a.locked, a.created_at age,
						c.user_name author
					FROM 'posts' a
					INNER JOIN 'votes' b ON a.id = b.post_id
					INNER JOIN 'users' c ON b.user_id = c.id
					WHERE a.locked = 0
						AND b.comment_id IS NULL
						AND b.upvote = 1
						AND a.id = b.post_id
						AND a.sub_id = ?
					GROUP BY a.id, b.post_id
					ORDER BY COUNT(*) DESC;
				]],
                "v_hot_" .. s.name,
                s.id
            )
        end

        -- Hot sort frontpage
        db.query(
            [[
					CREATE VIEW IF NOT EXISTS ?
					AS
					SELECT
						(SELECT COUNT(*) upvotes FROM 'votes' b WHERE b.post_id = a.id AND b.comment_id IS NULL AND b.upvote = 1) upvotes,
						(SELECT COUNT(*) upvotes FROM 'votes' b WHERE b.post_id = a.id AND b.comment_id IS NULL AND b.upvote = 0) downvotes,
						(SELECT COUNT(*) num_comments FROM 'comments' d WHERE d.post_id = a.id) num_comments,
						a.title, a.url, a.over_18, a.locked, a.created_at age,
						c.user_name author
					FROM 'posts' a
					INNER JOIN 'votes' b ON a.id = b.post_id
					INNER JOIN 'users' c ON b.user_id = c.id
					WHERE a.locked = 0
						AND b.comment_id IS NULL
						AND b.upvote = 1
						AND a.id = b.post_id
					GROUP BY a.id, b.post_id
					ORDER BY COUNT(*) DESC;
			]],
            "v_hot_frontpage"
        )
    end,

    -- create Users with random user_names
    [14] = function()
        local subreddits = Forum:select()

        for i = 1, math.random(10, 100) do
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

            for j = 1, #subreddits do
                if math.random(2) > 1 then
                    -- Use the real row ids, not the loop counters (which only
                    -- coincide with ids on a pristine, in-order database).
                    Subscriptions:create({
                        user_id = s.id,
                        subreddit_id = subreddits[j].id,
                    })
                end
            end
        end
    end,

    -- loop through all Subreddits and create some Posts for each
    [15] = function()
        local subreddits = Forum:select()

        -- ipairs: `sub` is the row. `for x in pairs(t)` would bind the index.
        for _, sub in ipairs(subreddits) do
            misc:generate_posts(sub.id, math.random(1, 3))
        end
    end,

    -- rss feed
    [16] = function()
        local subreddits = Forum:select()

        for _, sub in ipairs(subreddits) do
            if sub.feeds and #sub.feeds ~= 0 then
                for feed_url in string.gmatch(sub.feeds, '([^,]+)') do
                    -- RSS fetches hit the network; never let one failed feed
                    -- abort the whole migration.
                    local ok, err = pcall(function()
                        misc:rss_feed(sub.name, feed_url)
                    end)
                    if not ok then
                        print("rss_feed failed for " .. sub.name .. " (" .. feed_url .. "): " .. tostring(err))
                    end
                end
            end
        end
    end,

    -- cast Votes on posts in each subreddit
    [20] = function()
        local posts = Posts:select()

        for _, post in ipairs(posts) do
            misc:generate_post_votes(post.id, math.random(5, 20))
        end
    end,

    -- create Comments on each post
    [30] = function()
        local posts = Posts:select()

        for _, post in ipairs(posts) do
            misc:generate_comments(post.id, math.random(5))
        end
    end,

    -- create 10 votes on each comment
    [40] = function()
        local posts = Posts:select()

        for _, post in ipairs(posts) do
            misc:generate_comment_votes(post.id, math.random(10))
        end
    end,

    [99] = function()
        -- db.query("PRAGMA vacuum")
        -- db.query("PRAGMA optimize")
    end,

    -- classify text : https://github.com/leafo/lapis-bayes
    [1439944992] = require("lapis.bayes.schema").run_migrations,
}

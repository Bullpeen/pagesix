--- Migrations
-- @script migrations

local db     = require "lapis.db"
local json = require("cjson")

local Users = require("src.models.users")
local Pagesix = require("src.models.pagesix")
local Subreddits = require("src.models.subreddits")
local io = require("io")
local Lorem = require("src.utils.lorem")

math.randomseed(os.clock()*100000000000)

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
      user_pass = "hunter42!"
    })
  end,

  -- create initial subreddits
  [3] = function()
    -- TODO figure out utils module
    local data = {}
    local path = "/var/data/initial_subs.json"
    local file = io.open(path, "rb")

    if file then
      local content = file:read "*a" -- *a or *all reads the whole file
      file:close()
      data = json.decode(content)
      -- require 'pl.pretty'.dump(data)
      -- print("Read in " .. #data .. " subreddits from " .. path)
    end

    for _, sub in ipairs(data) do
      -- print("About to create new sub: " .. sub.name .. ".")
      local s, e = Subreddits:create({
        name = sub.name,
        description = sub.description or "",
        creator_id = sub.creator_id or 1,
      })
      if not s then
        print("error creating " .. s.name)
        print(e)
      end
      Subreddits:create_db_tables(s.id)
    end
  end,

  -- create 100 users with random user_names
  [4] = function()
    for i = 1, 100 do
      local s, e = Users:create({
        user_name = "user" .. i,
        user_email = "user" .. i .. "@localhost",
        user_pass = "hunter42!"
      })
      if not s then
        print("error creating " .. s.user_name)
        print(e)
        break
      end
    end
  end,

  -- loop through all subreddits and create some posts for each
  [5] = function()
    local subs = Subreddits:select()
    local users = Users:select()
    for _, sub in ipairs(subs) do
      -- print("About to create 5-20 posts for " .. sub.name .. ".")
      local table_name = sub.id .. "_posts"
      for i = 1, math.random(5,20) do
        local s, e = db.insert(table_name, {
          title = Lorem:sentence(),
          permalink = "/r/" .. sub.name .. "/comments/" .. i,
          url = "http://www.example.com/" .. i,
          user_id = math.random(1, #users),
        })
        if not s then
          print("error creating " .. s.title)
          print(e)
          break
        end
      end
    end

  end,

  -- create 50-100 comments for each post in each subreddit
  [6] = function()
    local subs = Subreddits:select()
    local users = Users:select()

    for _, sub in ipairs(subs) do
      -- print("About to create 10 comments for each post in " .. sub.name .. ".")
      local table_name = sub.id .. "_posts"
      local posts = db.select("* from ?", table_name)

      for _, post in ipairs(posts) do

        for i = 1, math.random(20,100) do
          local tbl = {
            post_id = post.id,
            user_id = math.random(1, #users), -- #users
            body = Lorem:text(),
          }

          -- set a variable 25% chance of creating a top-level comment for this post.
          local coin = math.random(1, 4)
          if i > 1 and coin > 1 then
            tbl.parent_comment_id = math.random(1, i)
            -- tbl.body = tbl.body .. " In reply to comment " .. tbl.parent_comment_id .. "."
          end

          local tbl_name = sub.id .. "_comments"
          local s, e = db.insert(tbl_name, tbl)

          if not s then
            print("error creating " .. s.body)
            print(e)
            break
          end
        end
      end
    end
  end,

  -- classify text : https://github.com/leafo/lapis-bayes
  [1439944992] = require("lapis.bayes.schema").run_migrations,
}

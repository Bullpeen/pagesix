--- Migrations
-- @script migrations

local db     = require "lapis.db"
-- local schema = require("lapis.db.schema")
-- local types  = schema.types
local json = require("cjson")
-- local misc = require("utils.misc")

local Users = require("src.models.users")
local Pagesix = require("src.models.pagesix")
-- local Posts = require("src.models.posts")
local io = require("io")

-- local Subreddit = require("src.models.subreddit")
local Subreddits = require("src.models.subreddits")

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

  [4] = function()
    -- loop through all subreddits and create 10 posts for each
    local subs = Subreddits:select()
    for _, sub in ipairs(subs) do
      print("About to create 10 posts for " .. sub.name .. ".")
      local table_name = sub.id .. "_posts"
      for i = 1, 10 do
        print(i)

        local s, e = db.insert(table_name, {
          title = "Post " .. i .. " for " .. sub.name,
          permalink = "http://www.example.com/" .. i,
          url = "http://www.example.com/" .. i,
          user_id = 1,
        })
        if not s then
          print("error creating " .. s.title)
          print(e)
          break
        end
      end
    end

  end,

  -- classify text : https://github.com/leafo/lapis-bayes
  [1439944992] = require("lapis.bayes.schema").run_migrations,
}

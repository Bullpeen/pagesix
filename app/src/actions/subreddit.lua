--- Subreddit action
-- @module action.subreddit

-- local assert_error = require("lapis.application").assert_error
-- local assert_valid = require("lapis.validate").assert_valid
-- local csrf         = require "lapis.csrf"
local db     = require "lapis.db"
local schema = require("lapis.db.schema")
-- local types  = schema.types

local Subreddits   = require("models.subreddits")
local Sub_posts    = require("models.subreddit_posts")
-- local Sub_post_votes    = require("models.subreddit_votes")
-- local Sub_comments = require("models.subreddit_comments")

return {
	before = function(self)
		-- query subreddits for id
		print("MICHAEL " .. self.params.subreddit .. ".")
		local res = db.select("id FROM 'subreddits' WHERE name=?", self.params.subreddit)
		local id = res[1].id
		print ("ID: " .. res[1].id)
		-- local id = 2 -- TODO do not hardcode

		local posts_table    = id .. "_posts"
		local comments_table = id .. "_comments"
		local votes_table    = id .. "_votes"
		local modlog_table    = id .. "_modlog"
		
		print("posts table: " .. posts_table)
		print("comments table: " .. comments_table)
		print("votes table: " .. votes_table)
		print("modlog table: " .. modlog_table)

		-- :check(name)
		-- 1. check if it is valid
		-- 2. check if it exists in Subreddits table
		-- 3. check if its tables exist
		-- 4. if not, create them

		-- Check if subreddit is nil or empty
		-- if name == nil or name == '' then
		-- 	print("Subreddit is unknown: " .. name)
		-- 	return self:write({ redirect_to = self:url_for("homepage") })
		-- end

		-- Check if sub exist in Subreddits table
		-- local should_exist = Subreddits:should_exist(name)
		-- require 'pl.pretty'.dump(should_exist)
		-- if next(should_exist) == nil then
		-- 	print "Subreddit not found"
		-- 	return self:write({ redirect_to = self:url_for("homepage") })
		-- end

		-- Check if tables exist
		-- local does_exist = Subreddit:tables_exist(posts_table)
		-- require 'pl.pretty'.dump(does_exist)
		-- if next(does_exist) == nil then
		-- 	Subreddit:new(name)
		-- end

		-- self.posts = self:get_posts(posts_table)
		self.posts = db.select("* FROM ?", posts_table)
	end,

	-- https://github.com/karai17/lapis-chan/blob/master/app/src/utils/generate.lua
	on_error = function(self)
		return { render = "subreddit"}
	end,

	GET = function(self)
		return { render = "subreddit" }
	end,
}

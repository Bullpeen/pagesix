--- Subreddits model
-- @module models.subreddit

-- local db    = require "lapis.db"

local Model = require("lapis.db.model").Model
-- local Silva = require 'silva'

local id = 1
-- local id
local sp_table = id .. "_posts"
print("The table be used is: " .. sp_table)

local Subreddit_posts = Model:extend(sp_table, {
	constraints = {
		--- Apply constraints
		-- @tparam table self
        -- @tparam table value User data
		-- @treturn string error
		title = function(self, value)
            -- title is maximum 256 characters
            if string.len(value) > 256 then
                return "Title is too long"
            end

            -- title is minimum 2 characters
            if string.len(value) < 1 then
                return "Title is too short"
            end

        end,

        url = function(self, value)
            -- local uri, err = Silva:new(value)

            -- if not uri then
            --     return("invalid URL: " .. err)
            -- end
        end,

        body = function(self, value)
            if self.is_self and string.len(value) > 0 then
                return "Only self posts can have body text"
            end

            -- body text is maximum 16kb
            if string.len(value) > 16384 then
                return "Body text is too long"
            end
        end,
    },

    relations = {
		{ "user",           belongs_to="Users"},

        { "subreddit",      has_one="Subreddits"},
        { "comments",
            has_many="Comments",
            where = {sub_id = id},
            order = "id desc",
            key = "post_id"
        },
        -- { "votes",
        --     has_many="Votes",
        --     where = {sub_id = id},
        --     order = "id desc",
        --     key = "post_id"
        -- },

		-- { "top_posts",
        --     has_many = "Posts",
        --     where = {sub_id = id},
        --     order = "id desc",
        --     key = "author"
        -- },
    }
})

function Subreddit_posts:top_posts(subreddit_id)
    -- query id .. "_posts" table for top 100 posts by score

    table = id .. "_posts"

    -- local upvotes = db.query("SELECT SUM(upvote) FROM '1_votes' WHERE post_id = '?' and upvote = '1'", post_id)
    -- local downvotes = db.query("SELECT SUM(upvote) FROM '1_votes' WHERE post_id = '?' and upvote = '0'", post_id)
    -- local votes = db.query("SELECT SUM(upvote) FROM '1_votes' WHERE post_id = '?'", post_id)

    local posts = db.query("SELECT *, COUNT(*) AS row_count FROM ? WHERE post_id = post_id, ORDER BY score DESC LIMIT 100", id .. table, subreddit_id)


end

-- function Subreddit_posts:new_posts()
-- end

-- function Subreddit_posts:controversial_posts()
-- end

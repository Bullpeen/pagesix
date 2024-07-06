--- Forum model
-- @module models.forum

local model = require("lapis.db.model")
local Model, enum = model.Model, model.enum
local db = require("lapis.db")

local Forum, Forum_mt = Model:extend("forum", {
	timestamp = true,

	-- url_params = function(self, req, ...)
	-- 	return "/"
	-- end,

	constraints = {
		--- Apply constraints when updating/inserting a Subreddit row, returns truthy to indicate error
		-- @tparam table self
		-- @tparam table value User data
		-- @treturn string error
		name = function(self, value)
			local reserved_subreddit_names = {
				"admin",
				"all",
				"controversial",
				"mods",
				"new",
				"pagesix",
				"popular",
				"random",
				"subscribed",
				"unsubscribed"
			}
			if reserved_subreddit_names[value] then
				return "Subreddit name is reserved"
			end

			-- check for valid length (2-64]
			if string.len(value) >= 64 then
				return "Subreddits must be less than 64 characters"
			end

			if string.len(value) < 2 then
				return "Subreddits must be at least 2 characters"
			end
		end,
	},

	relations = {
		{ "creator", belongs_to = "Users" },
		{ "moderators", has_many = "Users" },
		{ "subscribers", has_many = "Subscriptions" },
		{ "posts", has_many = "Posts" },

		-- TODO replace Forum_mt:get_frontpage() with a relation to Preload data
		-- { "frontpage",
		-- 	fetch = function()
		-- 		local v = "v_hot_" .. "frontpage"
		-- 		return db.select("* FROM ? LIMIT ?", v, 20)
		-- 	end,
		-- 	preload = nil,
		-- 	many = true
		-- }
	},
})


Forum.object_types = enum({
	ask                   = 1,
	aww                   = 2,
	best_of               = 3,
	blog                  = 4,
	books                 = 5,
	data_is_beautiful     = 6,
	documentaries         = 7,
	food                  = 8,
	funny                 = 9,
	futurology            = 10,

	gadgets               = 11,
	gaming                = 12,
	gifs                  = 13,
	history               = 14,
	ask_me_anything       = 15,
	internet_is_beautiful = 16,
	memes                 = 17,
	mildly_amusing        = 18,
	mildly_disappointing  = 19,
	mildly_infuriating    = 20,

	mildly_interesting    = 21,
	movies                = 22,
	music                 = 23,
	news                  = 24,
	pics                  = 25,
	politics              = 26,
	programming           = 27,
	science               = 28,
	space                 = 29,
	sports                = 30,

	technology            = 31,
	television            = 32,
	today_i_learned       = 33,
	videos                = 34,
	world_news            = 35,
	wtf                   = 36,
})

--- Get frontpage of a Subreddit from view
-- @tparam string subreddit_name e.g. 'technology', 'politics'
-- @tparam string sort e.g. 'hot', 'new', 'controversial' -- TODO use enum?
-- @treturn table posts
function Forum_mt:get_frontpage(subreddit_name, sort)
	-- TODO implement as a 'frontpage' relation on the Forum
	subreddit_name = subreddit_name or "frontpage"
	sort = sort or "hot"

	local v = "v_" .. sort .. "_" .. subreddit_name
	return db.select("* FROM ? LIMIT ?", v, 20)
end

return Forum

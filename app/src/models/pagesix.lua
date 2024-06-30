--- Pagesix model
-- @module models.pagesix

-- local create_index = schema.create_index
local schema = require("lapis.db.schema")
local types = schema.types

local Model = require("lapis.db.model").Model

local Pagesix = Model:extend("pagesix", {
	relations = {
		-- { "subreddits", has_many="Subreddits" },
		{ "moderator_ids", has_many = "Users" },
		{ "creator_id", has_one = "Users" },
	},
})

-- print("RUNNING MODELS.PAGE6")

function Pagesix:bootstrap()
	schema.create_table("users", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_name", types.text({ unique = true }) },
		{ "user_pass", types.text },
		{ "user_email", types.text },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		{ "deleted_at", types.integer({ null = true }) },
		{ "over_18", types.integer({ default = false }) },
		{ "verified_email", types.integer({ default = false }) },
	})

	schema.create_index("users", "user_name", { unique = true })

	schema.create_table("subscriptions", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_id", types.integer },
		{ "subreddit_id", types.integer },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(subreddit_id) REFERENCES subreddits(id)",

		"UNIQUE(user_id, subreddit_id)"
	})

	schema.create_table("reserved_usernames", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_name", types.text({ unique = true }) },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) }
	})

	schema.create_table("subreddits", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "name", types.text({ unique = true }) },

		{ "created_at", types.integer({ null = true }) },
		{ "deleted_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		{ "creator_id", types.integer({ deafault = 1 }) }, -- TODO rename
		{ "description", types.text({ null = true }) },
		{ "moderator_ids", types.text({ null = true }) },
		{ "nsfw", types.integer({ default = false }) },

		"FOREIGN KEY(creator_id) REFERENCES users(id)",
	})

	-- create_index("subreddits", "name", { unique = true })

	-- create subreddit table containing Posts by Users
	schema.create_table("posts", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_id", types.text },
		{ "sub_id", types.integer },
		{ "permalink", types.text({ unique = true }) },
		{ "title", types.text },
		{ "url", types.text },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		{ "locked", types.integer({ default = false }) },
		{ "edited", types.integer({ default = false }) },
		{ "is_self", types.integer({ default = false }) },
		{ "over_18", types.integer({ default = false }) },
		{ "body", types.text({ null = true }) },

		"FOREIGN KEY(sub_id) REFERENCES subreddits(id)",
		"FOREIGN KEY(user_id) REFERENCES users(id)",
	})

	-- create subreddit table containing Comments by Users
	schema.create_table("comments", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "post_id", types.integer },
		{ "user_id", types.integer },
		{ "permalink", types.text({ unique = true }) },
		{ "parent_comment_id", types.integer({ null = true }) },
		{ "body", types.text },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		{ "edited", types.integer({ default = false }) },
		{ "deleted", types.integer({ default = false }) },
		{ "is_submitter", types.integer({ default = false }) },
		{ "stickied", types.integer({ default = false }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(post_id) REFERENCES posts(id)",

		"UNIQUE(user_id, post_id, parent_comment_id)"
	})

	-- create each subreddit table containing Votes on Posts or Comments by Users
	schema.create_table("votes", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "user_id", types.integer },
		{ "post_id", types.integer },
		{ "comment_id", types.integer({ null = true }) },
		{ "upvote", types.integer({ default = true }) },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(post_id) REFERENCES 'posts(id)'",
		"FOREIGN KEY(comment_id) REFERENCES 'comments(id)'",

		"UNIQUE(user_id, post_id, comment_id)"
	})

	schema.create_table("modlog", {
		{ "id", types.integer({ unique = true, primary_key = true }) },
		{ "mod_id", types.text },
		{ "user_id", types.text({ null = true }) },
		{ "sub_id", types.text({ null = true }) }, -- TODO remove?
		{ "post_id", types.text({ null = true }) },
		{ "comment_id", types.text({ null = true }) },
		{ "action", types.integer({ null = true }) },
		{ "reason", types.text },

		{ "created_at", types.integer({ null = true }) },
		{ "updated_at", types.integer({ null = true }) },

		"FOREIGN KEY(mod_id) REFERENCES users(id)", -- TODO
		"FOREIGN KEY(user_id) REFERENCES users(id)",
		"FOREIGN KEY(sub_id) REFERENCES 'subreddits(id)'",
		"FOREIGN KEY(post_id) REFERENCES 'posts(id)'",
		"FOREIGN KEY(comment_id) REFERENCES 'comments(id)'"
	})
end

return Pagesix

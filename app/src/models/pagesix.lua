--- Pagesix model
-- @module models.pagesix

-- local db      = require "lapis.db"
local schema  = require("lapis.db.schema")
local create_index = schema.create_index
local types  = schema.types

local Model   = require("lapis.db.model").Model
local Pagesix = Model:extend("pagesix", {
	relations = {
		-- { "subreddit", has_many="Pagesix" },
		{ "moderator_ids", has_many="Users" },
		{ "creator_id", has_one="Users" }
	}
})

print("RUNNING MODELS.PAGE6")

function Pagesix:bootstrap()
	Pagesix:create_users_table()
	Pagesix:create_subscriptions_table()
	Pagesix:create_reserved_usernames_table()
	Pagesix:create_subreddits_table()
end

function Pagesix:create_users_table()
    schema.create_table("users", {
		{ "id",             types.integer { unique=true, primary_key=true }},
		{ "user_name",      types.text    { unique=true }},
		{ "user_pass",      types.text },
		{ "user_email",     types.text },

		{ "created_utc",    types.integer { default="1970-01-01 00:00:00" }},
		{ "deleted_utc",    types.integer { null=true }},
		{ "over_18",        types.integer { default=false }},
		{ "verified_email", types.integer { default=false }}
	})

	create_index("users", "user_name", { unique = true })
end

function Pagesix:create_subscriptions_table()
	schema.create_table("subscriptions", {
		{ "id",             types.integer { unique=true, primary_key=true }},
		{ "user_id",        types.integer },
		{ "subreddit_id",   types.integer }
	})
end

function Pagesix:create_reserved_usernames_table()
    schema.create_table("reserved_usernames", {
		{ "id",             types.integer { unique=true, primary_key=true }},
		{ "user_name",      types.text    { unique=true }},
		{ "created_at",   types.integer { default="1970-01-01 00:00:00" }},
		{ "updated_at",   types.integer { null=true }},
	})
end

function Pagesix:create_subreddits_table()
    schema.create_table("subreddits", {
		{ "id",            types.integer { unique=true, primary_key=true }},
		{ "name",          types.text { unique=true }},

		{ "created_at",   types.integer { default="1970-01-01 00:00:00" }},
		{ "deleted_at",   types.integer { null=true }},
		{ "updated_at",   types.integer { null=true }},
		{ "creator_id",    types.integer { deafault=1 }},
		{ "description",   types.text { null=true }},
		{ "moderator_ids", types.text { null=true }},
		{ "nsfw",          types.integer { default=false }}
	})

	-- create_index("subreddits", "name", { unique = true })
end

--- Get all subreddits
-- @treturn table subreddits
function Pagesix:get_all()
	-- use Paginator
	local subreddits = self:select("* FROM 'subreddits'")
	return subreddits and subreddits or false, "FIXME: listing subreddits failed"
end

--- Get all NSFW subreddits
-- @treturn table subreddits
function Pagesix:get_nsfw()
	local subreddits = self:select("* FROM 'subreddits' WHERE nsfw=?", 1)
	return subreddits and subreddits or false, "FIXME: listing NSFW subreddits failed"
end

return Pagesix

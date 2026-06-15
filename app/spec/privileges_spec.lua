--- RBAC privilege-matrix spec.
-- Exercises the role resolution + privilege matrix that gate moderation, plus
-- the Forum:can_moderate back-compat shim and the migration backfill.

local use_test_env = require("lapis.spec").use_test_env

describe("rbac privileges", function()
	use_test_env()

	local Users = require("models.users")
	local Forum = require("src.models.forum")
	local Moderators = require("src.models.moderators")
	local Roles = require("src.models.roles")
	local SiteRoles = require("src.models.site_roles")
	local Privileges = require("src.utils.privileges")
	local migrations = require("migrations")

	setup(function()
		require("spec.schema_helper")()
	end)

	-- use_test_env does not roll back SQLite rows between examples, so every
	-- example uses uniquely-named users/forums to stay isolated.
	local function make_user(name)
		return Users:create({
			user_name = name,
			user_pass = "password",
			user_email = name .. "@example.com",
		})
	end

	it("treats the forum creator as owner with every privilege", function()
		local owner = make_user("p_owner")
		local sub = Forum:create({ name = "p_owned", creator_id = owner.id })

		assert.same("owner", Privileges.role_of(owner.id, sub))
		for _, priv in ipairs(Privileges.ALL) do
			assert.is_true(Privileges.can(owner.id, sub, priv), "owner should hold " .. priv)
		end
	end)

	it("gives a moderator content powers but not governance powers", function()
		local owner = make_user("p_owner2")
		local mod = make_user("p_mod")
		local sub = Forum:create({ name = "p_modded", creator_id = owner.id })
		Forum:add_moderator(sub.id, mod.id)

		assert.same("moderator", Privileges.role_of(mod.id, sub))
		-- content powers
		for _, priv in ipairs({
			"remove",
			"lock",
			"sticky",
			"approve",
			"manage_feeds",
			"accept_answer",
		}) do
			assert.is_true(Privileges.can(mod.id, sub, priv), "moderator should hold " .. priv)
		end
		-- owner-only governance powers
		for _, priv in ipairs({ "manage_mods", "edit_forum", "ban" }) do
			assert.is_false(Privileges.can(mod.id, sub, priv), "moderator should NOT hold " .. priv)
		end
	end)

	it("denies everything to a plain member", function()
		local owner = make_user("p_owner3")
		local member = make_user("p_member")
		local sub = Forum:create({ name = "p_public", creator_id = owner.id })

		assert.same("member", Privileges.role_of(member.id, sub))
		for _, priv in ipairs(Privileges.ALL) do
			assert.is_false(Privileges.can(member.id, sub, priv), "member should NOT hold " .. priv)
		end
	end)

	it("lets a site admin override every forum-level check", function()
		local owner = make_user("p_owner4")
		local admin = make_user("p_admin")
		local sub = Forum:create({ name = "p_admin_target", creator_id = owner.id })
		SiteRoles:grant(admin.id, "admin")

		assert.is_true(Privileges.is_admin(admin.id))
		-- admin holds no role in this forum, yet may do anything
		assert.same("member", Privileges.role_of(admin.id, sub))
		for _, priv in ipairs(Privileges.ALL) do
			assert.is_true(Privileges.can(admin.id, sub, priv), "admin should hold " .. priv)
		end
	end)

	it("returns false for missing user, forum, or privilege", function()
		local owner = make_user("p_owner5")
		local sub = Forum:create({ name = "p_guard", creator_id = owner.id })

		assert.is_false(Privileges.can(nil, sub, "remove"))
		assert.is_false(Privileges.can(owner.id, nil, "remove"))
		assert.is_false(Privileges.can(owner.id, sub, nil))
		assert.is_false(Privileges.can(owner.id, sub, "nonexistent_privilege"))
	end)

	it("Forum:can_moderate shim is true for owner/moderator, false for member", function()
		local owner = make_user("p_owner6")
		local mod = make_user("p_mod6")
		local member = make_user("p_member6")
		local sub = Forum:create({ name = "p_shim", creator_id = owner.id })
		Forum:add_moderator(sub.id, mod.id)

		assert.is_true(Forum:can_moderate(owner.id, sub))
		assert.is_true(Forum:can_moderate(mod.id, sub))
		assert.is_false(Forum:can_moderate(member.id, sub))
	end)

	it("Roles:assign is idempotent and create-if-absent (no downgrade)", function()
		local owner = make_user("p_owner7")
		local u = make_user("p_assign")
		local sub = Forum:create({ name = "p_assign_sub", creator_id = owner.id })

		Roles:assign(sub.id, u.id, "owner")
		Roles:assign(sub.id, u.id, "moderator") -- must NOT overwrite the owner role
		assert.same("owner", Roles:role_for(sub.id, u.id))
		assert.same(1, Roles:count("subreddit_id = ? AND user_id = ?", sub.id, u.id))
	end)

	it("migration [100] backfills creators (owner) and moderators (moderator)", function()
		local owner = make_user("p_bf_owner")
		local legacy_mod = make_user("p_bf_mod")
		local sub = Forum:create({ name = "p_backfill", creator_id = owner.id })
		-- Seed a legacy moderators-table row with no corresponding role row.
		Moderators:create({ subreddit_id = sub.id, user_id = legacy_mod.id })

		-- Re-running the migration is idempotent (create table if_not_exists,
		-- assign create-if-absent) and should pick up the legacy row.
		migrations[100]()

		assert.same("owner", Roles:role_for(sub.id, owner.id))
		assert.same("moderator", Roles:role_for(sub.id, legacy_mod.id))
	end)
end)

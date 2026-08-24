--- Delete your own account.
-- @module action.account_delete
--
-- GET renders the confirmation form, POST performs the deletion. Content is
-- reassigned to the anonymous account rather than destroyed -- see
-- `Users:delete_account`. CSRF is validated globally in app.lua's before_filter.

local Users = require("models.users")
local Password = require("src.utils.password")
local log = require("src.utils.log").tag("account_delete")

local function fail(self, message)
	self.form_error = message
	return { render = "account_delete" }
end

-- Whether to demand the account password as a second confirmation.
--
-- An OAuth account holds the bcrypt digest of a value nobody knows (see
-- utils/oauth), so there is no way to tell "has a password" from the digest
-- alone -- and demanding one would lock those users out of deleting their own
-- account. Presence of a linked identity is the usable signal: they proved
-- themselves to the provider instead.
local function needs_password(user)
	local OAuthIdentities = require("src.models.oauth_identities")
	return OAuthIdentities:find({ user_id = user.id }) == nil
end

return {
	before = function(self)
		if not self.current_user then
			return self:write({ redirect_to = self:url_for("login") })
		end
		-- The view names the account content is reattributed to.
		self.anonymous_name = Users.ANONYMOUS
	end,

	GET = function(self)
		self.needs_password = needs_password(self.current_user)
		return { render = "account_delete" }
	end,

	POST = function(self)
		local user = self.current_user
		self.needs_password = needs_password(user)

		-- Typing the username is the deliberate-action check; the session cookie
		-- alone should not be enough to destroy an account.
		if self.params.confirm ~= user.user_name then
			return fail(self, "Type your username exactly to confirm.")
		end
		if
			self.needs_password and not Password.verify(self.params.password or "", user.user_pass)
		then
			return fail(self, "That password is not correct.")
		end

		local ok, err = Users:delete_account(user.id)
		if not ok then
			log.error("failed to delete account " .. tostring(user.id) .. ": " .. tostring(err))
			return fail(self, "Could not delete the account. Please try again.")
		end

		self.session.current_user = nil
		-- Force the session write (see the logout route in src/auth.lua).
		self.session._dummy = true
		return { redirect_to = self:url_for("homepage") }
	end,
}

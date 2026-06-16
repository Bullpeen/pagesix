--- Begin an OAuth login: stash an anti-CSRF state and redirect to the provider.
-- @module action.oauth_start

local OAuth = require("src.utils.oauth")

return {
	-- GET /auth/:provider
	GET = function(self)
		local provider = self.params.provider
		if not OAuth.provider(provider) then
			return { redirect_to = self:url_for("login") }
		end

		local state = OAuth.gen_state()
		self.session.oauth_state = state
		local redirect_uri = self:build_url(self:url_for("oauth_callback", { provider = provider }))
		return { redirect_to = OAuth.authorize_url(provider, state, redirect_uri) }
	end,
}

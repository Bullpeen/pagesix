--- OAuth callback: validate state, exchange the code, link-or-create the user,
--- and sign them in.
-- @module action.oauth_callback

local OAuth = require("src.utils.oauth")

return {
	-- GET /auth/:provider/callback?code=...&state=...
	GET = function(self)
		local provider = self.params.provider
		if not OAuth.provider(provider) then
			return { redirect_to = self:url_for("login") }
		end

		-- Anti-CSRF: the returned state must match the one we stashed at start.
		local expected = self.session.oauth_state
		self.session.oauth_state = nil
		if not self.params.state or self.params.state ~= expected then
			return { redirect_to = self:url_for("login") }
		end

		local redirect_uri = self:build_url(self:url_for("oauth_callback", { provider = provider }))
		local profile = OAuth.identify(provider, self.params.code, redirect_uri)
		if not profile then
			return { redirect_to = self:url_for("login") }
		end

		local user = OAuth.link_or_create(provider, profile)
		if not user then
			return { redirect_to = self:url_for("login") }
		end

		self.session.current_user = user.user_name
		return { redirect_to = self:url_for("homepage") }
	end,
}

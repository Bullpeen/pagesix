--- OAuth2 authorization-code login helper.
--
-- Providers are configured under `config.oauth` (see config.lua), e.g.
--   oauth = { github = { client_id=, client_secret=, authorize_url=, token_url=,
--                        profile_url=, scope= } }
--
-- The network step (`identify`) is a single seam so tests can stub it; the pure
-- pieces (authorize_url, link_or_create) need no network.
-- @module utils.oauth

local util = require("lapis.util")

local OAuth = {}

--- Provider config table for `name`, or nil if not configured.
function OAuth.provider(name)
	local config = require("lapis.config").get()
	return name and (config.oauth or {})[name] or nil
end

--- An opaque anti-CSRF `state` value for the round trip.
function OAuth.gen_state()
	local t = {}
	for i = 1, 16 do
		t[i] = string.format("%02x", math.random(0, 255))
	end
	return table.concat(t)
end

--- The provider's authorization URL to redirect the user to, or nil.
-- @tparam string name provider key
-- @tparam string state anti-CSRF value
-- @tparam string redirect_uri our callback URL
function OAuth.authorize_url(name, state, redirect_uri)
	local p = OAuth.provider(name)
	if not p then
		return nil
	end
	local query = util.encode_query_string({
		client_id = p.client_id,
		redirect_uri = redirect_uri,
		scope = p.scope or "",
		state = state,
		response_type = "code",
	})
	return p.authorize_url .. "?" .. query
end

--- Exchange an authorization `code` for a normalized profile
-- `{ provider_user_id, username, email }`, or nil. Does the provider HTTP calls
-- (token exchange + profile fetch) via lua-resty-http when available; returns
-- nil when the runtime/HTTP isn't available (e.g. unit tests stub this whole
-- function).
function OAuth.identify(name, code, redirect_uri)
	local p = OAuth.provider(name)
	if not p or not code then
		return nil
	end
	local ok_http, http = pcall(require, "resty.http")
	local ok_json, json = pcall(require, "cjson.safe")
	if not ok_http or not ok_json then
		return nil
	end

	local httpc = http.new()
	local token_res = httpc:request_uri(p.token_url, {
		method = "POST",
		body = util.encode_query_string({
			client_id = p.client_id,
			client_secret = p.client_secret,
			code = code,
			redirect_uri = redirect_uri,
			grant_type = "authorization_code",
		}),
		headers = {
			["Content-Type"] = "application/x-www-form-urlencoded",
			["Accept"] = "application/json",
		},
		ssl_verify = true,
	})
	if not token_res or token_res.status ~= 200 then
		return nil
	end
	local token = (json.decode(token_res.body) or {}).access_token
	if not token then
		return nil
	end

	local prof_res = httpc:request_uri(p.profile_url, {
		method = "GET",
		headers = {
			["Authorization"] = "Bearer " .. token,
			["Accept"] = "application/json",
			["User-Agent"] = "pagesix",
		},
		ssl_verify = true,
	})
	if not prof_res or prof_res.status ~= 200 then
		return nil
	end
	local prof = json.decode(prof_res.body) or {}
	return {
		provider_user_id = prof.id or prof.sub,
		username = prof.login or prof.name or prof.preferred_username,
		email = prof.email,
	}
end

--- Find the local user linked to this provider identity, or create one (with an
-- unusable password, like the rss_bot system user) and link it. Returns the
-- user row, or nil if a username couldn't be allocated.
-- @tparam string provider
-- @tparam table profile { provider_user_id, username?, email? }
function OAuth.link_or_create(provider, profile)
	if not profile or profile.provider_user_id == nil then
		return nil
	end
	local OAuthIdentities = require("src.models.oauth_identities")
	local Users = require("models.users")
	local Password = require("src.utils.password")
	local pid = tostring(profile.provider_user_id)

	local identity = OAuthIdentities:find({ provider = provider, provider_user_id = pid })
	if identity then
		return Users:find(identity.user_id)
	end

	-- Derive a base username from the profile, then disambiguate on collisions
	-- (Users:create returns nil for a taken/reserved/invalid name).
	local base = tostring(profile.username or (provider .. pid)):gsub("[^%w_%-]", ""):sub(1, 24)
	if #base < 3 then
		base = "user_" .. base
	end
	local unusable =
		Password.hash("oauth-" .. provider .. "-" .. pid .. "-" .. tostring(os.clock()))
	local email = profile.email or (base .. "@oauth.local")

	local user
	for attempt = 0, 50 do
		local name = attempt == 0 and base or (base .. attempt)
		-- Check first: a duplicate user_name raises a UNIQUE error (the model's
		-- constraints only reject reserved names, not taken ones).
		if not Users:find({ user_name = name }) then
			user = Users:create({ user_name = name, user_email = email, user_pass = unusable })
			if user then
				break
			end
		end
	end
	if not user then
		return nil
	end

	OAuthIdentities:create({ user_id = user.id, provider = provider, provider_user_id = pid })
	return user
end

return OAuth

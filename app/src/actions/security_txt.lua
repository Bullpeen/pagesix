--- security.txt (RFC 9116) served at the canonical /.well-known/security.txt
--- (and at /security.txt for convenience).
-- @module action.security_txt

return {
	-- GET /.well-known/security.txt  |  GET /security.txt
	GET = function(self)
		-- RFC 9116 requires an Expires date in the future; refresh it a year out.
		local expires = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + 365 * 24 * 60 * 60)

		local body = table.concat({
			"Contact: " .. self:build_url("/"),
			"Contact: mailto:security@pagesix.example",
			"Expires: " .. expires,
			"Preferred-Languages: en",
			"",
		}, "\n")

		return {
			content_type = "text/plain",
			layout = false,
			body,
		}
	end,
}

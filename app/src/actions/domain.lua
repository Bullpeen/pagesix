--- Domain action
-- @module action.domain

return {
	before = function(self)
        self.domain = self.params.domain
	end,

	GET = function(self)
		return { render = "domain" }
	end
}

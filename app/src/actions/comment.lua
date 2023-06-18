--- Comment action
-- @module action.comment

return {
	before = function(self)
	end,

	GET = function(self)
		return { render = "comment" }
	end
}

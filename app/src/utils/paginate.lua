--- Slice an array into a page and return page metadata.
-- @module utils.paginate

--- @tparam table items the full (already-sorted) list
-- @tparam[opt=1] number page 1-based page number
-- @tparam[opt=25] number per_page page size
-- @treturn table the page's items
-- @treturn table info { page, per_page, total, has_prev, has_next }
return function(items, page, per_page)
	page = math.max(1, math.floor(tonumber(page) or 1))
	per_page = per_page or 25

	local total = #items
	local from = (page - 1) * per_page + 1
	local to = math.min(from + per_page - 1, total)

	local out = {}
	for i = from, to do
		out[#out + 1] = items[i]
	end

	return out,
		{
			page = page,
			per_page = per_page,
			total = total,
			has_prev = page > 1,
			has_next = page * per_page < total,
		}
end

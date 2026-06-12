--- Paginate a comment thread by ROOT comment, keeping each root's subtree whole.
-- @module utils.paginate_thread
--
-- `rows` must be the depth-ordered thread `Comments:thread` returns: each root
-- (depth 0) is immediately followed by all of its descendants (the recursive
-- CTE orders by a materialized path). Slicing those flat rows by a fixed count
-- would orphan replies across page boundaries, so we page over the *roots* and
-- always emit each selected root together with its whole subtree.
--
-- @tparam table rows depth-ordered thread rows (each has a numeric `depth`)
-- @tparam[opt=1] number page 1-based page number
-- @tparam[opt=25] number per_page root comments per page
-- @treturn table the page's rows (roots + their descendants)
-- @treturn table info { page, per_page, total, has_prev, has_next } where
--   `total` counts root comments
return function(rows, page, per_page)
	page = math.max(1, math.floor(tonumber(page) or 1))
	per_page = per_page or 25

	-- Indices in `rows` where each root subtree begins.
	local roots = {}
	for i, c in ipairs(rows) do
		if tonumber(c.depth) == 0 then
			roots[#roots + 1] = i
		end
	end

	local total = #roots
	local from_root = (page - 1) * per_page + 1
	local to_root = math.min(from_root + per_page - 1, total)

	local out = {}
	if from_root <= total then
		local start_i = roots[from_root]
		-- Up to (but not including) the first root of the next page, or the end.
		local end_i = roots[to_root + 1] and (roots[to_root + 1] - 1) or #rows
		for i = start_i, end_i do
			out[#out + 1] = rows[i]
		end
	end

	return out, {
		page = page,
		per_page = per_page,
		total = total,
		has_prev = page > 1,
		has_next = page * per_page < total,
	}
end

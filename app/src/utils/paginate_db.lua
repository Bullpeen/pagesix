--- Pagination for queries that slice in SQL.
-- @module utils.paginate_db
--
-- `utils.paginate` slices an array the caller already fetched in full; this is
-- its counterpart for queries that push LIMIT/OFFSET down to the database.
--
-- "Is there a next page?" is answered by asking for **one row more** than the
-- page needs and seeing whether it arrives, so a listing costs one query rather
-- than a page query plus a `COUNT(*)` over the same filters. The extra row is
-- trimmed before rendering, and `total` is therefore not reported -- no view
-- uses it (see `fragments/page_nav.etlua`).
--
--     local page, per_page, limit, offset = P.window(self.params.page, 25)
--     local rows = Posts:get_listing({ sort = sort, limit = limit, offset = offset })
--     self.posts, self.pagination = P.finish(rows, page, per_page)

local M = {}

--- Resolve a requested page into the query's LIMIT/OFFSET.
-- @tparam[opt=1] number|string page 1-based page number (request param)
-- @tparam[opt=25] number per_page rows shown per page
-- @treturn number page the normalized page number
-- @treturn number per_page
-- @treturn number limit rows to request (`per_page + 1`, the lookahead row)
-- @treturn number offset
function M.window(page, per_page)
	page = math.max(1, math.floor(tonumber(page) or 1))
	per_page = per_page or 25
	return page, per_page, per_page + 1, (page - 1) * per_page
end

--- Trim the lookahead row and describe the page.
-- @tparam table rows what the query returned (up to `per_page + 1` rows)
-- @tparam number page
-- @tparam number per_page
-- @treturn table the page's rows
-- @treturn table info { page, per_page, has_prev, has_next }
function M.finish(rows, page, per_page)
	local items = {}
	for i = 1, math.min(#rows, per_page) do
		items[i] = rows[i]
	end
	return items,
		{
			page = page,
			per_page = per_page,
			has_prev = page > 1,
			has_next = #rows > per_page,
		}
end

return M

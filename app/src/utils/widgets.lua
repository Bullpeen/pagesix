--- Small HTML widgets shared across templates, where etlua's parameterless
--- `render` can't pass per-row values (e.g. inside a posts/comments loop).
-- @module utils.widgets

local Widgets = {}

--- A vote control: up/down arrows around a score. Progressive enhancement -- a
-- plain <form> POST is the no-JS fallback; Datastar intercepts the submit and
-- patches the score span (id `<kind>-score-<id>`) in place via SSE.
-- @tparam string kind "post" or "comment"
-- @tparam number id
-- @tparam number score net score to display
-- @tparam string csrf the CSRF token
-- @treturn string HTML
function Widgets.votes(kind, id, score, csrf)
	local base = "/vote/" .. kind .. "/" .. id
	local function arrow(dir, glyph)
		local url = base .. "/" .. dir
		return (
			'<form class="inline-form" method="POST" action="%s" '
			.. "data-on:submit__prevent=\"@post('%s', {headers:{'X-Csrf-Token': $csrf}})\">"
			.. '<input type="hidden" name="csrf_token" value="%s">'
			.. '<button class="vote %s" type="submit" aria-label="%svote">%s</button></form>'
		):format(url, url, csrf, dir, dir, glyph)
	end
	return ('<div class="votes">%s<span class="score" id="%s-score-%s">%s</span>%s</div>'):format(
		arrow("up", "&#9650;"),
		kind,
		id,
		score,
		arrow("down", "&#9660;")
	)
end

return Widgets

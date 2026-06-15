--- Simple static info pages (about / faq / help / contact)
-- @module action.static
--
-- One action backs several literal routes; the page is chosen by request path
-- and rendered through the shared `page` view (name + HTML content).

local PAGES = {
	["/about"] = {
		name = "About Page Six",
		content = [[
			<p>Page Six is a small, self-hostable link-sharing site &mdash; a
			Reddit-style community built with
			<a href="https://leafo.net/lapis/">Lapis</a> on OpenResty and SQLite.</p>
			<p>Browse the <a href="/subreddits">list of communities</a>, or
			<a href="/submit">submit a link</a> once you have an account.</p>
		]],
	},
	["/faq"] = {
		name = "FAQ",
		content = [[
			<h2>How do I post?</h2>
			<p>Create an account, then use <a href="/submit">submit</a> to share a
			link or write a self/text post (Markdown is supported, with a preview).</p>
			<h2>I forgot my password.</h2>
			<p>Use the <a href="/password">password reset</a> page to get a reset
			link for your account.</p>
			<h2>How is the front page ordered?</h2>
			<p>By a hot ranking; you can also sort by
			<a href="/new">new</a>, <a href="/top">top</a>, and
			<a href="/controversial">controversial</a>.</p>
		]],
	},
	["/help"] = {
		name = "Help",
		content = [[
			<p>Need a hand? Start with the <a href="/faq">FAQ</a>.</p>
			<ul>
				<li><a href="/subreddits">List of communities</a></li>
				<li><a href="/contact">Contact / report a problem</a></li>
			</ul>
		]],
	},
	["/contact"] = {
		name = "Contact",
		content = [[
			<p>This is a demo deployment. To report spam, abuse, or a bug, open an
			issue on the
			<a href="https://github.com/bullpeen/pagesix">project repository</a>.</p>
		]],
	},
}

return {
	GET = function(self)
		local page = PAGES[self.req.parsed_url.path]
		if not page then
			return { status = 404, layout = false, "Not Found" }
		end
		self.page = page
		return { render = "page" }
	end,
}

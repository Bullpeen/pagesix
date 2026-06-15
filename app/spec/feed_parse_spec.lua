--- Unit specs for the RSS/Atom feed parser (no network, no DB).

local feed_parse = require("src.utils.feed_parse")

describe("feed_parse", function()
	it("parses RSS 2.0 items (title, link, guid)", function()
		local xml = [[<?xml version="1.0"?>
			<rss version="2.0"><channel>
				<title>Example</title>
				<item><title>First</title><link>https://e.example/1</link><guid>g1</guid></item>
				<item><title>Second</title><link>https://e.example/2</link></item>
			</channel></rss>]]
		local entries = feed_parse(xml)
		assert.same(2, #entries)
		assert.same("First", entries[1].title)
		assert.same("https://e.example/1", entries[1].link)
		assert.same("g1", entries[1].guid)
		-- missing guid falls back to the link (so dedup still works)
		assert.same("https://e.example/2", entries[2].guid)
	end)

	it("parses Atom entries (link href + id)", function()
		local xml = [[<?xml version="1.0"?>
			<feed xmlns="http://www.w3.org/2005/Atom">
				<title>Atom Example</title>
				<entry>
					<title>Hello Atom</title>
					<link rel="alternate" href="https://a.example/post"/>
					<link rel="self" href="https://a.example/self"/>
					<id>urn:uuid:1234</id>
				</entry>
			</feed>]]
		local entries = feed_parse(xml)
		assert.same(1, #entries)
		assert.same("Hello Atom", entries[1].title)
		assert.same("https://a.example/post", entries[1].link) -- prefers rel=alternate
		assert.same("urn:uuid:1234", entries[1].guid)
	end)

	it("skips entries with no link and caps long titles", function()
		local long = string.rep("x", 400)
		local xml = "<rss><channel>"
			.. "<item><title>no link here</title></item>"
			.. "<item><title>"
			.. long
			.. "</title><link>https://e.example/ok</link></item>"
			.. "</channel></rss>"
		local entries = feed_parse(xml)
		assert.same(1, #entries) -- the link-less item is dropped
		assert.same(300, #entries[1].title)
	end)

	it("returns empty for malformed or empty input", function()
		assert.same(0, #feed_parse(""))
		assert.same(0, #feed_parse(nil))
		assert.same(0, #feed_parse("<not really xml"))
	end)
end)

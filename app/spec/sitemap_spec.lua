-- Pure-Lua spec for the sitemap XML builder (no lapis/DB). Runs in the fast loop.
local sitemap = require("src.utils.sitemap")

describe("sitemap builder", function()
	it("wraps urls in a urlset with the sitemaps.org namespace", function()
		local xml = sitemap({ { loc = "https://x.example/" } })
		assert.truthy(xml:find('<?xml version="1.0" encoding="UTF-8"?>', 1, true))
		assert.truthy(xml:find('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"', 1, true))
		assert.truthy(xml:find("<loc>https://x.example/</loc>", 1, true))
		assert.truthy(xml:find("</urlset>", 1, true))
	end)

	it("emits only the date part of a lastmod", function()
		local xml = sitemap({ { loc = "https://x.example/p/1", lastmod = "2024-03-04 12:30:00" } })
		assert.truthy(xml:find("<lastmod>2024-03-04</lastmod>", 1, true))
	end)

	it("omits lastmod when absent or malformed", function()
		local xml = sitemap({
			{ loc = "https://x.example/a" },
			{ loc = "https://x.example/b", lastmod = "n/a" },
		})
		assert.is_nil(xml:find("<lastmod>", 1, true))
	end)

	it("XML-escapes the loc", function()
		local xml = sitemap({ { loc = "https://x.example/?a=1&b=2" } })
		assert.truthy(xml:find("a=1&amp;b=2", 1, true))
		assert.is_nil(xml:find("a=1&b=2", 1, true))
	end)

	it("handles an empty url list", function()
		local xml = sitemap({})
		assert.truthy(xml:find("<urlset", 1, true))
		assert.is_nil(xml:find("<url>", 1, true))
	end)
end)

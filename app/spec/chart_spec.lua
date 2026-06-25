--- Unit spec for utils/chart: server-rendered inline SVG bar charts.

describe("chart", function()
	local chart = require("src.utils.chart")

	local function count(haystack, needle)
		local _, n = haystack:gsub(needle, "")
		return n
	end

	describe("vbars", function()
		it("draws one <rect> per value inside an <svg>", function()
			local svg = chart.vbars({ 1, 5, 3 }, { title = "t" })
			assert.truthy(svg:match("^<svg"))
			assert.truthy(svg:match("</svg>$"))
			assert.same(3, count(svg, "<rect"))
		end)

		it("handles an empty series", function()
			local svg = chart.vbars({}, {})
			assert.same(0, count(svg, "<rect"))
		end)

		it("does not divide by zero on an all-zero series", function()
			local svg = chart.vbars({ 0, 0, 0 }, {})
			assert.same(3, count(svg, "<rect"))
		end)
	end)

	describe("hbars", function()
		it("draws a bar per item and escapes labels", function()
			local svg = chart.hbars({
				{ label = "alpha", value = 10 },
				{ label = "<b>&", value = 4 },
			}, { title = "top" })
			assert.same(2, count(svg, "<rect"))
			assert.truthy(svg:find("alpha", 1, true))
			-- The hostile label is XML-escaped, not emitted raw.
			assert.truthy(svg:find("&lt;b&gt;&amp;", 1, true))
			assert.is_nil(svg:find("<b>&", 1, true))
		end)

		it("handles no items", function()
			assert.same(0, count(chart.hbars({}, {}), "<rect"))
		end)
	end)
end)

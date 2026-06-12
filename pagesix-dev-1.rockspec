package = "pagesix"
version = "dev-1"

source = {
  url = "git+https://github.com/bullpeen/pagesix.git"
}

description = {
  summary = "Reddit clone",
  detailed = [[
  ]],
  homepage = "https://github.com/bullpeen/pagesix",
  maintainer = "Michael Burns <michael@mirwin.net>",
  license = "AGPL"
}

dependencies = {
  "lua ~> 5.1",
  "argparse",             -- needed for some cmd scripts
  "bcrypt",
  "luabitop",
  "moonscript",

  "lapis >= 1.16.0",

  "http ~> 0.4",
  "lapis-annotate ~> 2.0",
  "lapis-bayes ~> 1.3",
  "lapis-console ~> 1.2",
  "lapis-redis ~> 1.0",
  "luajit-geoip ~> 2.1",
  "tableshape >= 2.6",    -- Test the shape or structure of a Lua table, https://luarocks.org/modules/leafo/tableshape
  "web_sanitize ~> 1.5",  -- Lua library for sanitizing untrusted HTML, https://luarocks.org/modules/leafo/web_sanitize

  "basexx",               -- base2, base16, base32, base64, base85 encoding & decoding
  "cmark",                -- markdown
  "hasher",               -- hash functions, https://github.com/edubart/lua-hasher
  "inspect",              -- formats tables for debugging, https://github.com/kikito/inspect.lua
  "lester",               -- unit tests, https://github.com/edubart/lester
  "luacov",               -- test coverage, https://github.com/lunarmodules/luacov
  "lpeg_patterns",        -- parses IP addrs, URIs, email addrs, https://github.com/daurnimator/lpeg_patterns
  "lpeg",                 -- improved regex-like pattern matching, https://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html
  -- "lrandom",           -- random numbers based on the Mersenne Twister
  "lsqlite3",
  "lua-cjson",
  "lua-resty-http",
  "lua-resty-mail",
  "lua-silva",            -- parse URLs, https://luarocks.org/modules/fperrad/lua-silva
  "luaexpat",             -- Simple API for XML parser, https://luarocks.org/modules/lunarmodules/luaexpat
  "feedparser",           -- rss, atom parser
  "luaossl",
  "luasec",
  "luasocket",
  "markdown",             -- md to html, https://luarocks.org/modules/mpeterv/markdown
  "penlight",
  "redis-lua",
}

build = {
  type = "none",
}

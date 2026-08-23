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

  "lapis >= 1.19.0",   -- latest; faster url_for, db.clause OR-combining, simulate_request

  -- NB: `~> x.y` is luarocks' pessimistic operator -- it means ">= x.y, < x.(y+1)",
  -- so these have to be bumped by hand to pick up a new minor release.
  "http ~> 0.4",
  "lapis-annotate ~> 2.1",
  "lapis-bayes ~> 1.6",
  "lapis-console ~> 1.2",
  "lapis-redis ~> 1.0",
  "luajit-geoip ~> 2.1",
  "tableshape >= 2.7",    -- Test the shape or structure of a Lua table, https://luarocks.org/modules/leafo/tableshape
  "web_sanitize ~> 1.7",  -- Lua library for sanitizing untrusted HTML, https://luarocks.org/modules/leafo/web_sanitize

  "basexx",               -- base2, base16, base32, base64, base85 encoding & decoding
  "cmark",                -- markdown
  "hasher",               -- hash functions, https://github.com/edubart/lua-hasher
  "inspect",              -- formats tables for debugging, https://github.com/kikito/inspect.lua
  "lester",               -- unit tests, https://github.com/edubart/lester
  "luacov",               -- test coverage, https://github.com/lunarmodules/luacov
  "luacheck",             -- lua linter, https://github.com/lunarmodules/luacheck
  "lpeg_patterns",        -- parses IP addrs, URIs, email addrs, https://github.com/daurnimator/lpeg_patterns
  "lpeg",                 -- improved regex-like pattern matching, https://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html
  -- "lrandom",           -- random numbers based on the Mersenne Twister
  "lsqlite3",
  "lua-cjson",
  "lua-resty-http",
  "lua-resty-mail",
  -- NB: dropped "lua-silva" here -- it was commented "parse URLs" but is
  -- actually a shell-glob/PCRE matcher (and was never installed or required).
  -- URL parsing uses luasocket's socket.url instead (see src/utils/url.lua).
  "luaexpat",             -- Simple API for XML parser, https://luarocks.org/modules/lunarmodules/luaexpat
  "feedparser",           -- rss, atom parser
  "luaossl",
  "luasec",
  "luasocket",            -- sockets; also socket.url, our URL parser
  "markdown",             -- md to html, https://luarocks.org/modules/mpeterv/markdown
  "penlight",
  "redis-lua",
}

build = {
  type = "none",
}

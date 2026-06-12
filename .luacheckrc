-- luacheck configuration
std = "luajit"

-- OpenResty / nginx global, available at runtime.
read_globals = { "ngx" }

exclude_files = { "app/static" }

ignore = {
	"212", -- unused argument (Lapis actions receive self/req they don't always use)
	"213", -- unused loop variable
	"631", -- line is too long
}

-- Spec files run under busted (describe/it/setup/assert/... globals).
files["app/spec"] = {
	std = "+busted",
}

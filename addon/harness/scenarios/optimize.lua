-- With Optimize on, Lua's collector is held from the module's file until the loading screen ends, and
-- then it runs again. Held, garbage piles up; running, it is taken away as it is made.
harness.include("lib/game.lua")

local function growth()
	collectgarbage("collect")
	local before = collectgarbage("count")
	for _ = 1, 300000 do local _ = {} end
	return collectgarbage("count") - before
end

EverlookDB = { qol = { optimize = { enabled = true } } }
harness.load_addon("Everlook")
harness.load_addon("Everlook_Optimize")
harness.check("the module holds the collector while loading", Everlook.optimize.held())
local before = collectgarbage("count")
for _ = 1, 300000 do local _ = {} end
local held_growth = collectgarbage("count") - before
harness.check("garbage piles up while it is held", held_growth > 8000)

game.login()
harness.check("logging in does not end the hold, the loading screen does", Everlook.optimize.held())
harness.event("LOADING_SCREEN_DISABLED")
harness.check("the end of the loading screen starts the collector again", not Everlook.optimize.held())
harness.check("and it runs again, so garbage is taken away as it is made", growth() < 4000)

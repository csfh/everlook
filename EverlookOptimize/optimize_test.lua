local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookOptimize")

local gc, heap = {}, 1000
local realCollect = collectgarbage
collectgarbage = function(option)
	if option == "count" then return heap end
	gc[#gc + 1] = option
	return 0
end
local loggedIn = false
IsLoggedIn = function() return loggedIn end
local timers = {}
C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end

t.load("EverlookOptimize")
local O = Everlook:GetAddon("EverlookOptimize")

check(O.db.holdGC == true, "starts on")
check(gc[1] == "stop" and O:IsHolding(), "the collector stops as the file loads")
check(timers[1] and timers[1].seconds == 8, "an 8-second fallback is set")

t.fire("PLAYER_LOGIN")
t.fire("PLAYER_ENTERING_WORLD")
check(O:IsHolding(), "it keeps holding through login")

t.fire("LOADING_SCREEN_DISABLED")
check(gc[2] == "restart" and not O:IsHolding(), "the end of the loading screen starts it again")

timers[1].fn()
t.fire("PLAYER_LOGOUT")
check(#gc == 2, "it restarts once and never runs a full collection")

-- The other ways out, on fresh loads of the same file.
local function reload(saved)
	Everlook.addons.EverlookOptimize = nil
	EverlookDB.EverlookOptimize = saved
	gc, timers = {}, {}
	assert(loadfile(dir .. "/optimize.lua"))("EverlookOptimize", {})
	t.fire("ADDON_LOADED", "EverlookOptimize")
	return Everlook:GetAddon("EverlookOptimize")
end

O = reload(nil)
heap = 500 * 1024
t.fire("ADDON_LOADED", "SomeOtherAddon")
check(gc[2] == "restart", "a heap past 400 MB starts it again")
heap = 1000

O = reload(nil)
timers[1].fn()
check(gc[2] == "restart", "the 8-second fallback starts it again")

O = reload(nil)
t.change("EverlookOptimize_holdGC", false)
check(gc[2] == "restart", "turning it off starts it again")

O = reload({ holdGC = false })
check(#gc == 0 and not O:IsHolding(), "off from last session: nothing is held")

loggedIn = true
O = reload(nil)
check(#gc == 0, "loaded after login: nothing is held")

collectgarbage = realCollect
t.done()

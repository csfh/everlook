local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookFlightTime")

UIParent = t.widget("UIParent")
local now, onTaxi = 1000, true
GetTime = function() return now end
UnitOnTaxi = function() return onTaxi end
UnitFactionGroup = function() return "Alliance" end
GetRealmName = function() return "Realm" end
local nodes = { { name = "Ironforge", kind = "CURRENT" }, { name = "Stormwind", kind = "REACHABLE" }, { name = "Menethil", kind = "REACHABLE" } }
NumTaxiNodes = function() return #nodes end
TaxiNodeName = function(i) return nodes[i].name end
TaxiNodeGetType = function(i) return nodes[i].kind end
local hooks = {}
hooksecurefunc = function(name, fn) hooks[name] = fn end

-- A /reload mid-flight: the saved flight is picked up again.
EverlookDB.EverlookFlightTime = {
	current = { key = "Realm:Alliance:Ironforge>Stormwind", origin = "Ironforge", destination = "Stormwind", started = 990 },
}
t.load("EverlookFlightTime")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFlightTime")
local poller = EverlookFlightTimePoller
local frame = EverlookFlightTimeFrame
local function tick(at) now = at poller.scripts.OnUpdate(poller, 0.3) end

check(F.db.show and F.db.remaining, "timer and time remaining start on")
check(F.label == "Flight Time", "its name stays its name: the settings catalog sorts by it")
check(hooks.TakeTaxiNode ~= nil, "hooks TakeTaxiNode")
tick(1000)
check(frame:IsShown() and F.text.text == "Stormwind  0:10", "a reload in the air keeps timing from takeoff")

-- Landing records the route.
onTaxi = false
tick(1050)
local route = F.db.routes["Realm:Alliance:Ironforge>Stormwind"]
check(route and route.seconds == 60 and route.samples == 1, "landing remembers how long the route took")
check(not frame:IsShown() and F.db.current == nil and poller.scripts.OnUpdate == nil, "and hides the timer and stops watching")

-- Second flight on the same route shows time left.
hooks.TakeTaxiNode(2)
onTaxi = true
tick(2000)
tick(2030)
check(F.text.text == "Stormwind  0:30  (~0:30 left)", "a known route shows the time left")
check(F.db.current and F.db.current.started == 2000, "the flight in progress is saved for a reload")

t.change("EverlookFlightTime_remaining", false)
tick(2040)
check(F.text.text == "Stormwind  0:40", "time left can be turned off")
t.change("EverlookFlightTime_remaining", true)

onTaxi = false
tick(2080)
route = F.db.routes["Realm:Alliance:Ironforge>Stormwind"]
check(route.samples == 2 and route.seconds == 70, "a second flight updates the average")

-- A flight under a second isn't remembered.
hooks.TakeTaxiNode(3)
onTaxi = true
tick(3000)
onTaxi = false
tick(3000.5)
check(F.db.routes["Realm:Alliance:Ironforge>Menethil"] == nil, "a flight under a second isn't remembered")

-- A flight asked for that never takes off is dropped after 10 seconds.
now = 4000
hooks.TakeTaxiNode(3)
tick(4005)
check(poller.scripts.OnUpdate ~= nil, "a requested flight is watched while it waits to take off")
tick(4011)
check(poller.scripts.OnUpdate == nil and not frame:IsShown(), "a flight that never takes off is dropped after 10 seconds")

-- No CURRENT node: nothing is timed.
nodes[1].kind = "REACHABLE"
hooks.TakeTaxiNode(2)
check(poller.scripts.OnUpdate == nil, "without a known origin nothing is timed")
nodes[1].kind = "CURRENT"

-- Turning it off mid-flight hides the timer and drops the measurement.
now = 5000
hooks.TakeTaxiNode(2)
onTaxi = true
tick(5000)
check(frame:IsShown(), "timer shows in the air")
t.change("EverlookFlightTime_show", false)
check(not frame:IsShown() and F.db.current == nil and poller.scripts.OnUpdate == nil, "turning it off hides it and drops the flight")
hooks.TakeTaxiNode(2)
check(poller.scripts.OnUpdate == nil, "while off, new flights aren't timed")

t.done()

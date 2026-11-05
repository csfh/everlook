local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookGroundEffects")

local defaults = { groundEffectDensity = "64", groundEffectDist = "70", groundEffectFade = "80" }
local cvars = { groundEffectDensity = "64", groundEffectDist = "70", groundEffectFade = "80" }
local writes = {}
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) writes[#writes + 1] = name .. "=" .. value cvars[name] = value return true end
GetCVarDefault = function(name) return defaults[name] end

t.load("EverlookGroundEffects")
t.fire("PLAYER_LOGIN")
local G = Everlook:GetAddon("EverlookGroundEffects")

check(not G.db.density and not G.db.distance and not G.db.fade, "all three start off")
check(#writes == 0, "off at login changes nothing")
check(t.has("checkbox density") and t.has("slider densityValue") and t.has("checkbox fade") and t.has("slider fadeValue"),
	"page has a checkbox and slider for each")
local density = t.settings.EverlookGroundEffects_densityValue.slider
check(density.min == 0 and density.max == 512 and density.step == 16, "density slider runs 0 to 512 in 16s")

t.change("EverlookGroundEffects_density", true)
check(cvars.groundEffectDensity == "256" and cvars.groundEffectDist == "70", "turning density on sets only density")

t.change("EverlookGroundEffects_densityValue", 512)
check(cvars.groundEffectDensity == "512", "moving its slider sets it at once")

t.change("EverlookGroundEffects_distance", true)
t.change("EverlookGroundEffects_fade", true)
check(cvars.groundEffectDist == "500" and cvars.groundEffectFade == "500", "distance and fade set from their sliders")

t.change("EverlookGroundEffects_density", false)
check(cvars.groundEffectDensity == "64" and cvars.groundEffectDist == "500", "turning one off resets only that one")

writes = {}
t.change("EverlookGroundEffects_densityValue", 100)
check(#writes == 2 and cvars.groundEffectDensity == "64", "a slider whose checkbox is off changes nothing")

t.done()

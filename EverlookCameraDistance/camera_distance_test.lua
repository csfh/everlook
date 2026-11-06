local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookCameraDistance")

local cvars = { cameraDistanceMaxZoomFactor = "1.9" }
local writes = {}
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) writes[#writes + 1] = name .. "=" .. value cvars[name] = value return true end
GetCVarDefault = function() return "1.9" end

t.load("EverlookCameraDistance")
t.fire("PLAYER_LOGIN")
local C = Everlook:GetAddon("EverlookCameraDistance")

check(C.db.change == true and C.db.distance == 2.6, "starts on, at 260%")
check(cvars.cameraDistanceMaxZoomFactor == "2.6", "login sets the zoom factor")
check(t.has("checkbox change") and t.has("slider distance"), "page has the checkbox and slider")
local slider = t.settings.EverlookCameraDistance_distance.slider
check(slider.min == 1 and slider.max == 4 and slider.step == 0.1 and slider.format(2.6) == "260%", "slider runs 100% to 400%")

t.change("EverlookCameraDistance_distance", 4)
check(cvars.cameraDistanceMaxZoomFactor == "4", "moving the slider sets it at once")

t.change("EverlookCameraDistance_change", false)
check(cvars.cameraDistanceMaxZoomFactor == "1.9", "turning it off puts the game's default back")

writes = {}
t.change("EverlookCameraDistance_distance", 3)
check(#writes == 0, "while off, the slider changes nothing")

GetCVarDefault = function() return nil end
t.change("EverlookCameraDistance_change", true)
t.change("EverlookCameraDistance_change", false)
check(cvars.cameraDistanceMaxZoomFactor == "2.6", "no game default: falls back to ours")

writes = {}
t.change("EverlookCameraDistance_change", false)
check(#writes == 0, "a value this session didn't write is never reset")

cvars.cameraDistanceMaxZoomFactor = nil
t.change("EverlookCameraDistance_change", true)
check(#writes == 0, "a client without the setting is left alone")

t.done()

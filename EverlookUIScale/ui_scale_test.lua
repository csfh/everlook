local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookUIScale")

local cvars = { useUiScale = "1", uiscale = "0.9" }
GetCVar = function(name) return cvars[name] end
local screenHeight = 1440
GetPhysicalScreenSize = function() return 2560, screenHeight end

local scale, sets = 0.9, 0
UIParent = t.widget("UIParent")
function UIParent.GetScale() return scale end
function UIParent.SetScale(_, value) scale, sets = value, sets + 1 end

t.load("EverlookUIScale")
t.fire("PLAYER_LOGIN")
local U = Everlook:GetAddon("EverlookUIScale")

check(U.db.pixelPerfect == false, "starts off")
check(t.has("checkbox pixelPerfect") and t.has("dropdown pixels"), "page has the checkbox and the size list")
check(U.db.pixels == 0, "size starts following the game's slider")

local function labels()
	local out = {}
	for _, choice in ipairs(U.Sizes()) do out[#out + 1] = choice[1] .. "=" .. choice[2] end
	return table.concat(out, "; ")
end
screenHeight = 3384
check(labels() == "0=Follow the game's UI Scale; 2=Tiny, 45% (2 screen pixels per pixel); "
	.. "3=Small, 68% (3 screen pixels per pixel); 4=Medium, 91% (4 screen pixels per pixel); "
	.. "5=Large, 113% (5 screen pixels per pixel); 6=Huge, 136% (6 screen pixels per pixel)", "6K: sharp sizes from 45% to 136%")
screenHeight = 1080
check(labels() == "0=Follow the game's UI Scale; 1=Small, 71% (1 screen pixel per pixel); "
	.. "2=Huge, 142% (2 screen pixels per pixel)", "1080p: 71% and 142%")
screenHeight = 400
check(labels() == "0=Follow the game's UI Scale; 1=Huge, 192% (1 screen pixel per pixel)", "a short screen still offers one pixel per unit")
screenHeight = 1440
check(sets == 0, "off at login: the game's scale is left alone")

t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(sets == 0, "off: the game's own scale changes are left alone")

t.change("EverlookUIScale_pixelPerfect", true)
check(math.abs(scale - 2 * 768 / 1440) < 1e-9, "on, 1440p at 90%: two pixels per unit, 107%")

t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(sets == 1, "an unchanged scale isn't set again")

scale = 0.9
t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(math.abs(scale - 2 * 768 / 1440) < 1e-9, "the game resetting the scale is undone")

screenHeight = 2160
scale, sets = 0.9, 0 -- the game sets its own scale on a resize
t.fire("DISPLAY_SIZE_CHANGED") t.fire("DISPLAY_SIZE_CHANGED") t.fire("DISPLAY_SIZE_CHANGED")
t.runSchedule()
check(sets == 1, "a burst of resizes rescales once")
check(math.abs(scale - 3 * 768 / 2160) < 1e-9, "4K at 90%: three pixels per unit, 107%")

t.combat = true
screenHeight = 1080
t.fire("DISPLAY_SIZE_CHANGED") t.runSchedule()
check(math.abs(scale - 3 * 768 / 2160) < 1e-9, "nothing changes in combat")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED") t.runSchedule()
check(math.abs(scale - 768 / 1080) < 1e-9, "the held change lands when combat ends: 1080p at 90%, 71%")

t.change("EverlookUIScale_pixelPerfect", false)
check(scale == 0.9, "off: the scale the game last set comes back")

sets = 0
t.fire("PLAYER_REGEN_ENABLED")
t.change("EverlookUIScale_pixelPerfect", false)
check(sets == 0, "a scale this session didn't write is never reset")

-- With Use UI Scale off the game picks its own scale; on a 6K screen that was 0.64, not 1.
cvars.useUiScale = "0"
scale = 0.64
t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(sets == 0, "off: the game choosing a new scale is left alone")
t.change("EverlookUIScale_pixelPerfect", true)
t.change("EverlookUIScale_pixelPerfect", false)
check(scale == 0.64, "and turning this off puts that scale back, not one worked out from the CVars")

t.combat = true
t.change("EverlookUIScale_pixelPerfect", true)
check(scale == 0.64, "switching it on in combat waits")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(math.abs(scale - 768 / 1080) < 1e-9, "and applies when combat ends")

screenHeight = 3384
scale = 1 -- the game's own scale after the resize
t.fire("DISPLAY_SIZE_CHANGED") t.runSchedule()
check(math.abs(scale - 4 * 768 / 3384) < 1e-9, "6K at 100%: four pixels per unit, 91%")

scale = 0.65 -- the player moves the game's slider
t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(math.abs(scale - 3 * 768 / 3384) < 1e-9, "the game's slider still sets the size: 6K at 65%, 68%")

screenHeight = 600
t.fire("DISPLAY_SIZE_CHANGED") t.runSchedule()
check(math.abs(scale - 768 / 600) < 1e-9, "never less than one pixel per unit")

GetPhysicalScreenSize = function() return 0, 0 end
sets = 0
t.fire("DISPLAY_SIZE_CHANGED") t.runSchedule()
check(sets == 0, "no screen size: the scale is left alone")

-- Choosing a size.
GetPhysicalScreenSize = function() return 2560, screenHeight end
screenHeight = 3384
t.change("EverlookUIScale_pixels", 3)
check(math.abs(scale - 3 * 768 / 3384) < 1e-9, "Small on 6K: 68%")
scale = 1
t.fire("UI_SCALE_CHANGED") t.runSchedule()
check(math.abs(scale - 3 * 768 / 3384) < 1e-9, "a chosen size ignores the game's slider")
screenHeight = 1080
t.fire("DISPLAY_SIZE_CHANGED") t.runSchedule()
check(math.abs(scale - 768 / 1080) < 1e-9, "a size this screen can't show follows the game's scale")
t.change("EverlookUIScale_pixels", 0)
t.change("EverlookUIScale_pixelPerfect", false)
sets = 0
t.change("EverlookUIScale_pixels", 2)
check(sets == 0, "while off, choosing a size changes nothing")

t.done()

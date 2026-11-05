local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookPreferences minimap button")

local button = EverlookMinimapButton
local prefs = EverlookPreferences
local function near(a, b) return math.abs(a - b) < 0.01 end

check(button ~= nil and prefs.button == button, "the button exists, named EverlookMinimapButton")
check(prefs.db.minimapAngle == 160 and EverlookDB.EverlookPreferences == prefs.db,
	"it starts at 160 degrees, saved in EverlookDB.EverlookPreferences")

local _, relativeTo, _, x, y = unpack(button.point)
check(relativeTo == Minimap and near(x, math.cos(math.rad(160)) * 75) and near(y, math.sin(math.rad(160)) * 75),
	"it sits on a circle just outside the minimap")

local logo = io.open(dir .. "/../Everlook/assets/logo.tga", "rb")
check(logo ~= nil, "the logo it shows is in Everlook/assets")
if logo then logo:close() end

-- Click toggles the settings, the same way /el does.
SettingsPanel:Hide()
t.reset()
button.scripts.OnClick(button)
check(has("open 1"), "click opens the Everlook settings")
SettingsPanel:Show()
t.reset()
button.scripts.OnClick(button)
check(has("close SettingsPanel") and not SettingsPanel:IsShown(), "click again closes them")

-- Drag: the angle follows the cursor around the minimap's centre (1000, 500).
button.scripts.OnDragStart(button)
check(button.scripts.OnUpdate ~= nil, "dragging follows the cursor")
t.cursor = { 1000, 600 } -- straight above
button.scripts.OnUpdate(button)
check(near(prefs.db.minimapAngle, 90), "cursor above the minimap moves it to the top")
_, _, _, x, y = unpack(button.point)
check(near(x, 0) and near(y, 75), "and places it there")
button.scripts.OnDragStop(button)
check(button.scripts.OnUpdate == nil and near(prefs.db.minimapAngle, 90), "drop stops following and keeps the angle")

t.done()

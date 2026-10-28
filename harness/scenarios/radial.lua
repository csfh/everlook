-- The radial menu with the real button, key and pointer: the key goes down over the ground, the wheel opens
-- where the pointer is, a flick picks a wedge, and the key coming up does what the wedge says.
harness.include("lib/game.lua")
harness.load_addon("Everlook")
harness.load_addon("Everlook_RadialMenu")
game.login()
Everlook.module.set("radial_menu", "enabled", true)

-- Nothing under the pointer but the world, as over open ground.
function UnitExists() return false end
function IsInGroup() return false end
function IsInRaid() return false end
local pings = {}
C_Ping = { SendMacroPing = function(kind) pings[#pings + 1] = kind end }

local key = EverlookRadialMenuButton
harness.check("the key's button exists, and nothing can click it with the mouse", key ~= nil and not key:IsMouseEnabled())
harness.move(960, 540)
key:Click("LeftButton", true)
harness.advance(0.3)
harness.check("holding the key over the ground opens the wheel", Everlook.radial_menu_wheel.is_open())
harness.snapshot("The wheel open over the ground")

local function wedge_toward(dx, dy)
	harness.move(960 + dx, 540 + dy)
	harness.advance(0.1)
	return Everlook.radial_menu_wheel.selected()
end
local chosen = wedge_toward(140, 0)
harness.check("a flick to the right chooses a wedge", chosen ~= nil)
harness.snapshot("A wedge chosen")
key:Click("LeftButton", false)
harness.advance(0.2)
harness.check("letting go closes the wheel", not Everlook.radial_menu_wheel.is_open())
local log = harness.secure_log()
harness.check("and sets the button to the wedge's macro, which the game then runs (" .. tostring(log[#log]) .. ")", log[#log] == "macro macrotext=/ping 2")
for _, e in ipairs(harness.errors()) do print("script error:", e) end
for _, m in ipairs(harness.missing()) do print("missing method:", m) end
for _, m in ipairs(harness.fields_read()) do print("field read unset:", m) end

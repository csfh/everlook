local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookSwingTimers")

Enum = { EditModeSwingTimerSetting = { Scale = 1 } }
local hooks = {}
hooksecurefunc = function(frame, method, fn)
	hooks[#hooks + 1] = { frame = frame, method = method, fn = fn }
end

-- A swing timer frame with an Edit Mode layout scale of 120%.
local function timer(name)
	local frame = { name = name, scale = 1.2 }
	function frame:IsInitialized() return true end
	function frame:HasSetting(setting) return setting == 1 end
	function frame:GetSettingValue() return 120 end
	function frame:SetScale(scale) self.scale = scale end
	function frame:UpdateSystem() end
	function frame:UpdateSystemSettingScale() end
	_G[name] = frame
	return frame
end
local main = timer("SwingTimerMainHandFrame")

t.load("EverlookSwingTimers")
t.fire("PLAYER_LOGIN")
local S = Everlook:GetAddon("EverlookSwingTimers")

check(S.db.change == false and S.db.scale == 0.5, "starts off, at 50%")
check(main.scale == 1.2, "off at login leaves the bars alone")
check(#hooks == 2, "hooks UpdateSystem and UpdateSystemSettingScale")

t.change("EverlookSwingTimers_change", true)
check(main.scale == 0.5, "turning it on sets the bar to the slider's scale")

t.change("EverlookSwingTimers_scale", 0.8)
check(main.scale == 0.8, "moving the slider resizes at once")

main.scale = 1.2
hooks[1].fn()
check(main.scale == 0.8, "Edit Mode resizing the bar is put back to ours")

t.combat = true
t.change("EverlookSwingTimers_scale", 0.6)
check(main.scale == 0.8, "in combat it waits")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(main.scale == 0.6, "and applies when combat ends")

local off = timer("SwingTimerOffHandFrame")
t.fire("ADDON_LOADED", "Blizzard_SwingTimer")
check(off.scale == 0.6, "bars that appear later get sized when Blizzard_SwingTimer loads")

t.change("EverlookSwingTimers_change", false)
check(main.scale == 1.2 and off.scale == 1.2, "turning it off puts back the Edit Mode layout's scale")

local ranged = timer("SwingTimerRangedFrame")
ranged.scale = 0.9
S:Apply()
check(ranged.scale == 0.9, "a bar this session never sized is never reset")

t.done()

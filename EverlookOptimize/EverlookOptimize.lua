local Optimize = Everlook:NewAddon("EverlookOptimize", {
	label = "Optimize",
	defaults = {
		holdGC = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookOptimize", {
	"collectgarbage",
	"C_Timer.After",
	"IsLoggedIn",
})

-- While the game loads, Lua allocates thousands of tables and strings, and the collector spends
-- part of the loading screen walking them. With this on, the collector is stopped as this file
-- loads and started again by whichever comes first: the end of the loading screen, a heap past
-- 400 MB, eight seconds, logging out, or turning this off. It never runs a full collection.
local CEILING_KB = 400 * 1024
local FALLBACK_SECONDS = 8
local EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "PLAYER_LOGOUT" }

local held = false

function Optimize:IsHolding()
	return held
end

function Optimize:Release()
	if not held then return end
	held = false
	collectgarbage("restart")
	for _, event in ipairs(EVENTS) do
		self:UnregisterEvent(event)
	end
end

local function onEvent(event)
	if event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_LOGOUT" or collectgarbage("count") > CEILING_KB then
		Optimize:Release()
	end
end

-- EverlookDB is already loaded here: Everlook's ADDON_LOADED came before this file ran.
-- Only a load that hasn't logged in yet is held, since no loading screen may end after that.
local saved = EverlookDB and EverlookDB.EverlookOptimize
if not (saved and saved.holdGC == false) and not IsLoggedIn() then
	held = true
	collectgarbage("stop")
	Everlook.Trace.Mark("gc_hold") -- the Performance page reads this
	for _, event in ipairs(EVENTS) do
		Optimize:RegisterEvent(event, onEvent)
	end
	C_Timer.After(FALLBACK_SECONDS, function() Optimize:Release() end)
end

function Optimize:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Developer")
	page:Checkbox("holdGC", "Hold the garbage collector while loading",
		"Pause Lua's garbage collector during login and reload, and start it again when the loading screen ends. Takes effect from the next load.")
end

function Optimize:OnSettingChanged(key, value)
	if key == "holdGC" and not value then self:Release() end
end

local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookHideClutter")

-- Blizzard frames that listen for their own events.
local function blizzardFrame(...)
	local frame = { registered = {} }
	for _, event in ipairs({ ... }) do frame.registered[event] = true end
	function frame:IsEventRegistered(event) return self.registered[event] == true end
	function frame:RegisterEvent(event) self.registered[event] = true end
	function frame:UnregisterEvent(event) self.registered[event] = nil end
	return frame
end
TalkingHeadFrame = blizzardFrame("TALKINGHEAD_REQUESTED")
ZoneTextFrame = blizzardFrame("ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA") -- INDOORS stopped by someone else
UIErrorsFrame = blizzardFrame("UI_ERROR_MESSAGE")
RaidWarningFrame = blizzardFrame("CHAT_MSG_RAID_WARNING")

StanceBar = { Update = function() t.log("stance update") end }
RegisterStateDriver = function(_, state, value) t.log("driver " .. state .. " " .. value) end
UnregisterStateDriver = function(_, state) t.log("undriver " .. state) end
securecallfunction = function(fn, ...) return fn(...) end

t.load("EverlookHideClutter")
t.fire("PLAYER_LOGIN")
local H = Everlook:GetAddon("EverlookHideClutter")

check(H.db.talkingHead and not H.db.zoneText and not H.db.errorMessages and not H.db.raidWarnings and not H.db.stanceBar,
	"only the talking head starts hidden")
check(not TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), "login hides the talking head")
check(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), "errors still show")

t.change("EverlookHideClutter_zoneText", true)
check(not ZoneTextFrame:IsEventRegistered("ZONE_CHANGED") and not ZoneTextFrame:IsEventRegistered("ZONE_CHANGED_NEW_AREA"),
	"turning an option on hides it at once")
t.change("EverlookHideClutter_zoneText", false)
check(ZoneTextFrame:IsEventRegistered("ZONE_CHANGED") and ZoneTextFrame:IsEventRegistered("ZONE_CHANGED_NEW_AREA"),
	"turning it off brings it back")
check(not ZoneTextFrame:IsEventRegistered("ZONE_CHANGED_INDOORS"), "an event something else had stopped stays stopped")

t.fire("PLAYER_ENTERING_WORLD")
t.fire("PLAYER_ENTERING_WORLD")
t.change("EverlookHideClutter_talkingHead", false)
check(TalkingHeadFrame:IsEventRegistered("TALKINGHEAD_REQUESTED"), "applying again doesn't lose what it stopped")

-- Stance bar: protected, so only out of combat.
t.combat = true
t.reset()
t.change("EverlookHideClutter_stanceBar", true)
check(#t.calls == 0, "combat holds the stance bar change")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(has("driver visibility hide"), "the change lands when combat ends")
t.reset()
t.change("EverlookHideClutter_stanceBar", false)
check(has("driver visibility show") and has("undriver visibility") and has("stance update"),
	"turning it off hands the bar back to Blizzard")

local driver = RegisterStateDriver
RegisterStateDriver = nil
t.reset()
t.change("EverlookHideClutter_stanceBar", true)
check(#t.calls == 0, "no state drivers on the client: the bar is left alone")
RegisterStateDriver = driver

t.done()

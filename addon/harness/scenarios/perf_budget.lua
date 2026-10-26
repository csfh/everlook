-- What a login costs in things that can be counted: frames made, events registered, frames that run a script
-- every frame. Times are printed for the reader and never asserted on, since they depend on the machine.
-- A number only goes up on purpose: raise a ceiling here in the same change that adds the thing it counts.
harness.include("lib/game.lua")
game.quests()
local names = { "Everlook", "Everlook_Fonts", "Everlook_Island" }
for _, name in ipairs({ "ActionBarSlots", "ActionShortcuts", "AutoLoot", "AutoRepair", "AutoResponses", "Bags", "CameraDistance", "ChatLayout", "CinematicSkip", "CompactChat",
	"FlightTime", "FriendConveniences", "GossipSkip", "GroundEffects", "HideClutter", "IslandBuffs", "IslandExperience", "IslandHearth", "IslandInvites", "IslandLoot",
	"IslandMail", "IslandProfessions", "IslandQuestNotices", "IslandReactions", "IslandRecap", "IslandReputation", "IslandShare", "IslandWarnings",
	"MinimapCoordinates", "Nameplates", "NameplateTitles", "OpenContainers", "QuestAutomation", "QuestLevels", "QuestNameplates", "QuestTextSize", "RadialMenu", "RewardMarks", "SellJunk",
	"SwingTimers", "TakeMail", "TooltipCursor", "TrackerTextSize", "UnitFrameNames", "UsefulTooltips" }) do
	names[#names + 1] = "Everlook_" .. name
end
local ids = {}
local register
local loading = debugprofilestop()
for index, name in ipairs(names) do
	if index == 2 then
		register = Everlook.module.register
		Everlook.module.register = function(module) ids[#ids + 1] = module.id; return register(module) end
	end
	assert(pcall(harness.load_addon, name))
end
loading = debugprofilestop() - loading
game.login()
harness.advance(1)

local off = harness.census()
print(string.format("modules off: %d frames, %d events, %d running an OnUpdate (all files loaded in %.0f ms)", off.frames, off.events, off.updating, loading))
harness.check("the whole suite makes few frames while every module is off (" .. off.frames .. ")", off.frames <= 30)
harness.check("and registers few events (" .. off.events .. ")", off.events <= 110)
harness.check("and no frame runs an OnUpdate every frame while idle (" .. off.updating .. ")", off.updating <= 0)

for _, id in ipairs(ids) do
	assert(pcall(Everlook.module.set, id, "enabled", true))
end
harness.advance(3)
local on = harness.census()
print(string.format("modules on: %d frames, %d events, %d running an OnUpdate", on.frames, on.events, on.updating))
harness.check("with every module on the frames stay bounded (" .. on.frames .. ")", on.frames <= 170)
harness.check("and so do the events (" .. on.events .. ")", on.events <= 110)
harness.check("and so do the frames that run an OnUpdate (" .. on.updating .. ")", on.updating <= 3)

-- The load trace the player reads on the Performance page is made while all this runs.
local trace = Everlook.trace and Everlook.trace.ledger
harness.check("the load trace names a span for the settings page and for modules starting", trace ~= nil and trace.spans.settings ~= nil and next(trace.spans) ~= nil)
local ms = 0
for label, span in pairs(trace and trace.spans or {}) do
	if label:sub(1, 7) == "module:" then ms = ms + span.ms end
end
print(string.format("modules started in %.1f ms; settings page %s ms, %s KB", ms, tostring(trace and trace.spans.settings and trace.spans.settings.ms), tostring(trace and trace.counts.settings_kb)))

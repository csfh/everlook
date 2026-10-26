-- Every Everlook addon at once, the way a player has them: each loads, the game logs in, a few seconds pass,
-- and no script raised an error.
harness.include("lib/game.lua")
game.quests()
local names = { "Everlook", "Everlook_Fonts", "Everlook_Island" }
for _, name in ipairs({ "ActionBarSlots", "ActionShortcuts", "AutoLoot", "AutoRepair", "AutoResponses", "Bags", "CameraDistance", "ChatLayout", "CinematicSkip", "CompactChat",
	"FlightTime", "FriendConveniences", "GossipSkip", "GroundEffects", "HideClutter", "IslandBuffs", "IslandExperience", "IslandHearth", "IslandInvites", "IslandLoot",
	"IslandMail", "IslandProfessions", "IslandQuestNotices", "IslandReactions", "IslandRecap", "IslandReputation", "IslandShare", "IslandWarnings",
	"MinimapCoordinates", "Nameplates", "NameplateTitles", "OpenContainers", "Optimize", "QuestAutomation", "QuestLevels", "QuestNameplates", "QuestTextSize", "RadialMenu", "RewardMarks", "SellJunk",
	"SwingTimers", "TakeMail", "TooltipCursor", "TrackerTextSize", "UnitFrameNames", "UsefulTooltips" }) do
	names[#names + 1] = "Everlook_" .. name
end
-- Every module is off until its player turns it on, so turn them all on to see them work.
local ids = {}
local register
for index, name in ipairs(names) do
	if index == 2 then
		register = Everlook.module.register
		Everlook.module.register = function(module) ids[#ids + 1] = module.id; return register(module) end
	end
	local loaded, why = pcall(harness.load_addon, name)
	harness.check(name .. " loads" .. (loaded and "" or ": " .. tostring(why):sub(1, 200)), loaded)
end
game.login()
harness.advance(1)
for _, id in ipairs(ids) do
	local ok, why = pcall(Everlook.module.set, id, "enabled", true)
	harness.check("module " .. id .. " turns on" .. (ok and "" or ": " .. tostring(why):sub(1, 160)), ok)
end
harness.advance(3)
local errors = harness.errors()
harness.check("no script raised an error while they ran" .. (#errors > 0 and (": " .. errors[1]:sub(1, 300)) or ""), #errors == 0)

-- Fields only the old test frames had. Reading one off a real frame gives nil and the code carries on wrongly.
local test_frame_only = { mouse = true, point = true, points = true, scripts = true, regions = true, shown = true, alpha = true, width = true, height = true,
	clicks = true, pass_through = true, attributes = true, scroll_child = true, scroll_offset = true, events = true, parent = true, name = true }
local offences = {}
for _, entry in ipairs(harness.fields_read()) do
	local field = entry:match("%.(.+)$")
	if field and test_frame_only[field] then offences[#offences + 1] = entry end
end
for _, m in ipairs(harness.missing()) do print("method looked up and not found:", m) end
harness.check("no addon read a field only the test frames have" .. (#offences > 0 and (": " .. table.concat(offences, ", ")) or ""), #offences == 0)

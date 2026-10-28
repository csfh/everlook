-- What the game tells an addon about the player and the world: the readouts the Everlook addons ask
-- for. One table, `game`, holds the state, so a scenario changes the world by changing it.
game = {
	level = 12, xp = 450, xp_max = 1000, money = 12345,
	hour = 14, minute = 5, combat = false,
	slots = { [1] = { 40, 50 }, [5] = { 10, 20 } },
	bags = { [0] = 6, [1] = 2 },
	guid = "Player-1-0A",
	name = "Tester", realm = "Stormrage",
}

function InCombatLockdown() return game.combat end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function UnitXP() return game.xp end
function UnitXPMax() return game.xp_max end
function UnitLevel() return game.level end
function UnitGUID() return game.guid end
function UnitName() return game.name, game.realm end
function GetMoney() return game.money end
function GetGameTime() return game.hour, game.minute end
function GetXPExhaustion() return nil end
function GetMaxPlayerLevel() return 60 end
function GetInventoryItemDurability(slot)
	local pair = game.slots[slot]
	if pair then return pair[1], pair[2] end
end
BACKPACK_CONTAINER = 0
NUM_BAG_SLOTS = 1
INVSLOT_FIRST_EQUIPPED = 1
INVSLOT_LAST_EQUIPPED = 19
C_Container = {
	GetContainerNumFreeSlots = function(bag) return game.bags[bag] or 0, 0 end,
	GetContainerNumSlots = function() return 0 end,
}
C_Map = {
	GetBestMapForUnit = function() return 37 end,
	GetPlayerMapPosition = function() return { x = 0.5, y = 0.25, GetXY = function() return 0.5, 0.25 end } end,
}

-- What the game sends once every addon is in.
function game.login()
	EventUtil.__login()
	harness.event("PLAYER_LOGIN")
	harness.event("PLAYER_ENTERING_WORLD", true, false)
end

-- Four quests in the log, two on the tracker, one selected.
function game.quests()
	game.quest_list = {
		{ questID = 21, title = "Nearby dangerous", level = 18, distance = 100 },
		{ questID = 22, title = "Suitable farther", level = 12, distance = 800 },
		{ questID = 23, title = "Ready to return", level = 40, distance = 400, ready = true },
		{ questID = 24, title = "Across the sea", level = 12, distance = 1, remote = true },
	}
	game.watched, game.selected = { 21, 22 }, 22
	for _, quest in ipairs(game.quest_list) do
		quest.objectives = { { text = "Collect things", numFulfilled = 1, numRequired = 6, finished = false } }
	end
	local function find(id)
		for _, quest in ipairs(game.quest_list) do if quest.questID == id then return quest end end
	end
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #game.quest_list end,
		GetInfo = function(index) return game.quest_list[index] end,
		GetNumQuestWatches = function() return #game.watched end,
		GetQuestIDForQuestWatchIndex = function(index) return game.watched[index] end,
		GetQuestObjectives = function(id) return find(id).objectives end,
		GetDistanceSqToQuest = function(id)
			local quest = find(id)
			return quest.distance and quest.distance * quest.distance, not quest.remote
		end,
		ReadyForTurnIn = function(id) return find(id).ready or false end,
	}
	C_SuperTrack = { GetSuperTrackedQuestID = function() return game.selected end }
end

function GetLocale() return "enUS" end

-- Takes a picture, after checking the island is in the state the picture is named for:
-- "closed", "open" (by hovering or pinned) or "pinned".
function game.snapshot(label, expected)
	local view = Everlook.island.view()
	local right = (expected == "closed" and view.mode == "closed")
		or (expected == "open" and view.mode == "open")
		or (expected == "pinned" and view.mode == "open" and view.pinned == true)
	harness.check("\"" .. label .. "\" is " .. expected .. " (mode " .. tostring(view.mode) .. ", pinned " .. tostring(view.pinned) .. ")", right)
	harness.snapshot(label)
end

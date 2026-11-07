local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookQuestRank")

local W = t.Widget
function W:EnableMouse(on) self.mouse = on end
function W:SetAllPoints() end
function W:GetFrameLevel() return 1 end

-- The quest log and the watch list. Watching puts the quest first, as Forever does; `appends`
-- switches to a client that adds it at the end.
local log = {} -- { questID, isOnMap, objectives = { numFulfilled }, complete }
local watched = {}
local appends = false
local cap = 3
local super = 0
local alt = false
local function find(list, id)
	for i, v in ipairs(list) do if v == id then return i end end
end
local function quest(id)
	for _, q in ipairs(log) do if q.questID == id then return q end end
end
local fire -- set below; watch changes fire their event like the game does
C_QuestLog = {
	GetNumQuestWatches = function() return #watched end,
	GetQuestIDForQuestWatchIndex = function(i) return watched[i] end,
	AddQuestWatch = function(id)
		if find(watched, id) or #watched >= cap then return false end
		table.insert(watched, appends and #watched + 1 or 1, id)
		t.log("add " .. id)
		fire("QUEST_WATCH_LIST_CHANGED", id, true)
		return true
	end,
	RemoveQuestWatch = function(id)
		local i = find(watched, id)
		if not i then return false end
		table.remove(watched, i)
		t.log("remove " .. id)
		fire("QUEST_WATCH_LIST_CHANGED", id, nil)
		return true
	end,
	SortQuestWatches = function() t.log("sort") end,
	GetNumQuestLogEntries = function() return #log + 1, #log end,
	GetInfo = function(i)
		if i == 1 then return { isHeader = true, title = "Zone" } end
		local q = log[i - 1]
		return q and { questID = q.questID, isOnMap = q.isOnMap }
	end,
	GetQuestObjectives = function(id)
		local list = {}
		for i, n in ipairs(quest(id).objectives) do list[i] = { numFulfilled = n, finished = n >= 5 } end
		return list
	end,
	IsComplete = function(id) return quest(id).complete == true end,
	GetDistanceSqToQuest = function(id) return quest(id).distance or 100 end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return super end }
Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = cap } }
UnitName = function() return "Hero" end
GetRealmName = function() return "Realm" end
IsAltKeyDown = function() return alt end
hooksecurefunc = function(tbl, name, fn)
	local original = tbl[name]
	tbl[name] = function(...) original(...) fn(...) end
end
function GameTooltip.Show() end

-- A tracker module with one active block per watched quest.
local blocks = {}
QuestObjectiveTracker = {
	blockTemplate = "QuestBlock",
	EndLayout = function() end,
	EnumerateActiveBlocks = function(_, callback)
		for _, block in ipairs(blocks) do callback(block) end
	end,
}
local function layout()
	blocks = {}
	for i, id in ipairs(watched) do
		blocks[i] = { id = id, template = "QuestBlock", HeaderButton = t.widget() }
	end
	QuestObjectiveTracker:EndLayout()
end

for i = 1, 5 do log[i] = { questID = 100 + i, objectives = { 0 }, isOnMap = false } end

t.load("EverlookQuestRank")
fire = t.fire
t.fire("PLAYER_LOGIN")
local QR = Everlook:GetAddon("EverlookQuestRank")
local function run() t.runSchedule() end
local function order() return table.concat(watched, " ") end
local function progress(id) quest(id).objectives[1] = quest(id).objectives[1] + 1 t.fire("QUEST_LOG_UPDATE") run() end

watched = { 101, 102 }
t.fire("QUEST_LOG_UPDATE")
run()
check(order() == "101 102" and not t.has("sort"), "starts off and changes nothing")

-- On
QR.db.rank = true
QR:OnSettingChanged("rank", true)
run()
check(order() == "101 102", "turning it on keeps what's tracked, in its order")
check(QR.db.characters["Hero-Realm"].activity[101] ~= nil, "and remembers it per character")

t.reset()
t.fire("QUEST_LOG_UPDATE")
run()
check(#t.calls == 0, "a reload's first look at the log counts as no activity")

progress(102)
check(order() == "102 101", "progress moves a quest to the top")

progress(104)
check(order() == "104 102 101", "progress on an untracked quest tracks it at the top")

progress(103)
check(order() == "103 104 102", "when the tracker is full, the oldest activity is untracked")

-- Completing, super-tracking, entering an area
quest(101).complete = true
t.fire("QUEST_LOG_UPDATE")
run()
check(order() == "101 103 104", "a quest ready to turn in moves to the top")

super = 102
t.fire("SUPER_TRACKING_CHANGED")
run()
check(order() == "102 101 103", "super-tracking a quest moves it to the top")

quest(104).isOnMap, quest(104).distance = true, 50
quest(105).isOnMap, quest(105).distance = true, 10
t.fire("ZONE_CHANGED_NEW_AREA")
run()
check(order() == "105 104 102", "entering two quests' area: both move up, the nearest on top")

-- One game re-sort, one re-apply
watched = { 102, 104, 105 }
t.reset()
t.fire("ZONE_CHANGED")
run()
check(order() == "105 104 102", "the game's re-sort is put back")
local adds = 0
for _, call in ipairs(t.calls) do if call:find("^add") then adds = adds + 1 end end
check(adds == 3, "in one pass")
t.reset()
t.fire("QUEST_LOG_UPDATE")
run()
check(#t.calls == 0, "and nothing more after it")

-- A game re-sort that sends a remove and an add for every quest is still no activity.
C_QuestLog.SortQuestWatches = function()
	local list = { unpack(watched) }
	for _, id in ipairs(list) do C_QuestLog.RemoveQuestWatch(id) end
	for i = #list, 1, -1 do C_QuestLog.AddQuestWatch(list[i]) end
end
local before = {}
for id, n in pairs(QR.db.characters["Hero-Realm"].activity) do before[id] = n end
C_QuestLog.SortQuestWatches()
t.fire("ZONE_CHANGED_NEW_AREA")
run()
local kept = true
for id, n in pairs(before) do if QR.db.characters["Hero-Realm"].activity[id] ~= n then kept = false end end
check(kept and order() == "105 104 102", "a re-sort that unwatches and rewatches everything changes no activity")
C_QuestLog.SortQuestWatches = function() t.log("sort") end

-- Objectives that arrive late are no activity.
log[6] = { questID = 106, objectives = {}, isOnMap = false }
t.fire("QUEST_LOG_UPDATE")
run()
log[6].objectives = { 2 }
t.fire("QUEST_LOG_UPDATE")
run()
check(order() == "105 104 102", "a quest whose objectives load late doesn't jump up")
table.remove(log, 6)

-- Manual untrack
C_QuestLog.RemoveQuestWatch(105)
t.fire("QUEST_LOG_UPDATE")
run()
check(order() == "104 102 101", "a quest you untrack stays untracked")
progress(105)
check(order() == "105 104 102", "until its next activity")

-- Combat and Shift
t.combat = true
progress(103)
check(order() == "105 104 102", "nothing changes in combat")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
run()
check(order() == "103 105 104", "and the change lands when combat ends")
t.shift = true
progress(101)
check(order() == "103 105 104", "holding Shift waits")
t.shift = false
t.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
run()
check(order() == "101 103 105", "and letting go applies it")

-- Pins
local made = {}
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent)
	local frame = createFrame(kind, name)
	frame.parent = parent
	made[#made + 1] = frame
	return frame
end
local function overlayOn(block)
	for _, frame in ipairs(made) do
		if frame.parent == block then return frame end
	end
end
layout()
check(not overlayOn(blocks[1]), "Alt-click to pin starts off and draws nothing")
QR.db.rank_pin = true
QR:OnSettingChanged("rank_pin", true)
run()
layout()
local state = QR.db.characters["Hero-Realm"]
local over = overlayOn(blocks[3])
check(over and over.shown and over.mouse == false, "on: each title gets a catcher that lets clicks through")
alt = true
t.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
check(over.mouse == true, "holding Alt makes it take the click")
over.scripts.OnClick(over)
run()
check(order() == "105 101 103" and state.pins[1] == 105, "Alt-clicking a title pins that quest to the top")
layout()
check(overlayOn(blocks[1]).mark.shown, "and marks it")
alt = false
t.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
check(overlayOn(blocks[1]).mouse == false, "letting go of Alt gives clicks back to the game")
progress(104)
check(order() == "105 104 101", "and stays there above newer activity")
QR.TogglePin(105)
progress(103)
check(order() == "103 105 104", "unpinned, it ranks by activity again")
QR.TogglePin(101)
run()
check(order() == "101 103 105", "pinning an untracked quest tracks it")

QR.db.rank_pin = false
QR:OnSettingChanged("rank_pin", false)
progress(104)
check(order() == "104 101 103", "with pinning off, pins rank like any other quest")
QR.db.rank_pin = true
QR:OnSettingChanged("rank_pin", true)
run()
check(order() == "101 104 103", "turning pinning back on restores them")

C_QuestLog.RemoveQuestWatch(101)
run()
check(#state.pins == 0 and order() == "104 103 105", "untracking a pinned quest yourself unpins it, and the next quest takes its place")

-- Pins are per character
local heroCounter = state.counter
UnitName = function() return "Alt" end
t.fire("QUEST_ACCEPTED", 102)
local other = QR.db.characters["Alt-Realm"]
check(other and other.counter == 1 and #other.pins == 0 and state.counter == heroCounter,
	"another character keeps its own activity and pins")
UnitName = function() return "Hero" end
QR.db.characters["Alt-Realm"] = nil
run()

-- A client that appends new watches: one rewrite reads back reversed, the next is in order.
appends = true
progress(105)
check(order() == "105 104 103", "a client that appends gets the order right after one look")
progress(102)
check(order() == "102 105 104", "and from then on")

-- Off
t.reset()
QR.db.rank = false
QR:OnSettingChanged("rank", false)
check(t.has("sort") and order() == "102 105 104", "turning it off gives the order back to the game and keeps the watches")
progress(103)
check(order() == "102 105 104", "and changes nothing after")
layout()
local drawn = false
for _, frame in ipairs(made) do if frame.shown then drawn = true end end
check(not drawn, "and draws no catchers or marks")

t.done()

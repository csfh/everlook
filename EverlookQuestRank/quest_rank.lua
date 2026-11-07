local QuestRank = Everlook:NewAddon("EverlookQuestRank", {
	label = "Quest Rank",
	defaults = {
		rank = false,
		rank_pin = false,
		rank_follow = false,
		-- [name-realm] = { pins = { questID in pin order }, activity = { [questID] = n }, counter = n }
		characters = {},
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookQuestRank", {
	"C_QuestLog.AddQuestWatch",
	"C_QuestLog.RemoveQuestWatch",
	"C_QuestLog.GetNumQuestWatches",
	"C_QuestLog.GetQuestIDForQuestWatchIndex",
	"C_QuestLog.SortQuestWatches",
	"C_QuestLog.GetNumQuestLogEntries",
	"C_QuestLog.GetInfo",
	"C_QuestLog.GetQuestObjectives",
	"C_QuestLog.IsComplete",
	"C_SuperTrack.GetSuperTrackedQuestID",
	"C_SuperTrack.SetSuperTrackedQuestID",
	"QuestObjectiveTracker.EndLayout",
	"QuestObjectiveTracker.EnumerateActiveBlocks",
	"GameTooltip",
	"GetRealmName",
	"GetTime",
	"InCombatLockdown",
	"IsAltKeyDown",
	"IsShiftKeyDown",
	"UnitName",
	"hooksecurefunc",
}, {
	"CampaignQuestObjectiveTracker.EndLayout",
	"Constants.QuestWatchConsts.MAX_QUEST_WATCHES",
	"C_QuestLog.GetDistanceSqToQuest",
	"C_SuperTrack.IsSuperTrackingAnything",
	"C_SuperTrack.IsSuperTrackingQuest",
	"QuestUtil.CanRemoveQuestWatch",
	"issecretvalue",
})

-- The game's cap on watched quests (QuestConstantsDocumentation.lua, 12.0.0: 25).
local function maxWatches()
	local consts = Constants and Constants.QuestWatchConsts
	return consts and consts.MAX_QUEST_WATCHES or 25
end

local LOGO = "Interface\\AddOns\\Everlook\\assets\\logo.tga"
local function readable(value)
	return not (issecretvalue and issecretvalue(value))
end

-- This character's ranking, kept in the account-wide settings.
local function character()
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	local characters = QuestRank.db.characters
	local state = characters[key]
	if not state then
		state = { pins = {}, activity = {}, counter = 0 }
		characters[key] = state
	end
	return state
end

local function bump(state, questID)
	state.counter = state.counter + 1
	state.activity[questID] = state.counter
end

local function pinIndex(state, questID)
	for i, id in ipairs(state.pins) do
		if id == questID then return i end
	end
end

local function unpin(state, questID)
	local i = pinIndex(state, questID)
	if i then table.remove(state.pins, i) end
end

-- The watch list: pinned quests in pin order, then every quest with activity, newest first, up
-- to `max`. `known` is the set of quests that may be watched; pins is a list, activity a map.
function QuestRank.Order(known, pins, activity, max)
	local order, taken = {}, {}
	for _, id in ipairs(pins) do
		if #order >= max then return order end
		if known[id] and not taken[id] then
			order[#order + 1], taken[id] = id, true
		end
	end
	local rest = {}
	for id in pairs(activity) do
		if known[id] and not taken[id] then rest[#rest + 1] = id end
	end
	table.sort(rest, function(a, b)
		if activity[a] ~= activity[b] then return activity[a] > activity[b] end
		return a < b
	end)
	for _, id in ipairs(rest) do
		if #order >= max then break end
		order[#order + 1] = id
	end
	return order
end

local function watches()
	local list = {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if id and readable(id) then list[#list + 1] = id end
	end
	return list
end

-- The quests in the log that go on the normal watch list. World quests and bonus objectives
-- (tasks, bounties) have a list of their own.
local function logQuests()
	local quests = {}
	local count = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, count or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and not info.isTask and not info.isBounty
			and readable(info.questID) and info.questID then
			quests[#quests + 1] = info
		end
	end
	return quests
end

-- The quests watched when we last looked: a quest that joins it since was tracked by you (or by
-- the game on accepting it), one that left it was untracked by you. Comparing sets, not
-- QUEST_WATCH_LIST_CHANGED payloads, keeps the game's own re-sort (SortQuestWatches on every zone
-- change) from looking like a change, whatever events it sends.
local lastSet
local unwatchable = {} -- quests the game refused to watch this session
local snapshots = {} -- [questID] = { sig, count, onMap }; in memory, so a reload counts nothing
local lastSuper -- the super-tracked quest we last saw
local pending = false -- an apply waits for combat or Shift to end
local refused -- the target the game didn't take last time, so we don't fight it
local followed -- the quest we last super-tracked as the tracker's top

local function asSet(list)
	local set = {}
	for _, id in ipairs(list) do set[id] = true end
	return set
end

-- Counts watches added or removed since we last looked, outside our own rewrites.
local function noticeWatchChanges(state)
	local now = watches()
	if lastSet then
		for _, id in ipairs(now) do
			if not lastSet[id] then bump(state, id) end
		end
		local nowSet = asSet(now)
		for id in pairs(lastSet) do
			if not nowSet[id] then
				-- You untracked it: it waits for its next activity.
				state.activity[id] = nil
				unpin(state, id)
			end
		end
	end
	lastSet = asSet(now)
end

local function canChange()
	return not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch()
end

-- Where AddQuestWatch puts a new watch. Forever 1.60.1 puts it first: a rewrite that added the
-- target in order read back exactly reversed (a session record, 2026-11-06). A client that
-- appends shows itself the same way, and the first rewrite it reorders flips this for the session.
local prepends = true
local flipped = false

-- Rewrites the watch list to `target`, keeping the run of watches that is already in place: the
-- start of the list when watches are appended, its end when they are put first. Everything else
-- is unwatched, then the rest of the target re-watched so it lands in order.
local function rewrite(current, target)
	local keep = 0
	local n, m = #current, #target
	if prepends then
		while keep < n and keep < m and current[n - keep] == target[m - keep] do keep = keep + 1 end
	else
		while keep < n and keep < m and current[keep + 1] == target[keep + 1] do keep = keep + 1 end
	end
	if keep == n and keep == m then return false end
	if prepends then
		for i = n - keep, 1, -1 do C_QuestLog.RemoveQuestWatch(current[i]) end
		for i = m - keep, 1, -1 do
			if C_QuestLog.AddQuestWatch(target[i]) == false then unwatchable[target[i]] = true end
		end
	else
		for i = n, keep + 1, -1 do C_QuestLog.RemoveQuestWatch(current[i]) end
		for i = keep + 1, m do
			if C_QuestLog.AddQuestWatch(target[i]) == false then unwatchable[target[i]] = true end
		end
	end
	return true
end

local function sameMembers(a, b)
	if #a ~= #b then return false end
	local set = asSet(a)
	for _, id in ipairs(b) do if not set[id] then return false end end
	return true
end

-- Super-tracks the tracker's top quest, once each time a new quest reaches the top: a quest you
-- super-track yourself, or clearing it, holds until the top changes. A map pin, waypoint or
-- other non-quest target you super-track is yours, and is left alone.
local function follow()
	if not QuestRank.db.rank_follow then return end
	local top = watches()[1]
	if not top or top == followed then return end
	local anything = C_SuperTrack.IsSuperTrackingAnything and C_SuperTrack.IsSuperTrackingAnything()
	local quest = C_SuperTrack.IsSuperTrackingQuest and C_SuperTrack.IsSuperTrackingQuest()
	if readable(anything) and readable(quest) and anything == true and quest == false then return end
	followed = top
	local current = C_SuperTrack.GetSuperTrackedQuestID()
	if readable(current) and current == top then return end
	-- Our own change: SUPER_TRACKING_CHANGED sees it as already known, so it isn't activity.
	lastSuper = top
	C_SuperTrack.SetSuperTrackedQuestID(top)
end

-- Puts the watch list in rank order. The tracker lists quests in watch order
-- (QuestObjectiveTrackerMixin:BuildQuestWatchInfos, 12.0.0).
local function order()
	if not canChange() then return end

	local state = character()
	local current = watches()
	local known = {}
	for _, info in ipairs(logQuests()) do
		if not unwatchable[info.questID] then known[info.questID] = true end
	end
	-- What's watched now is watchable, and starts in its current order below every quest
	-- with activity.
	local low = 0
	for _, n in pairs(state.activity) do low = math.min(low, n) end
	for i, id in ipairs(current) do
		known[id] = true
		if not state.activity[id] then state.activity[id] = low - i end
	end

	local pins = QuestRank.db.rank_pin and state.pins or {}
	local target = QuestRank.Order(known, pins, state.activity, maxWatches())
	local wanted = table.concat(target, ",")
	if wanted == refused then return end

	if not rewrite(current, target) then return end
	local now = watches()
	-- Every quest went on, in another order: the client adds watches the other way round.
	if table.concat(now, ",") ~= wanted and sameMembers(now, target) and not flipped then
		prepends, flipped = not prepends, true
		rewrite(now, target)
		now = watches()
	end
	lastSet = asSet(now)
	local after = table.concat(now, ",")
	refused = after ~= wanted and wanted or nil
end

function QuestRank.Apply()
	if not QuestRank.db.rank then return end
	if InCombatLockdown() or IsShiftKeyDown() then
		pending = true
		return
	end
	pending = false
	order()
	follow()
end

local function objectives(questID)
	local list = C_QuestLog.GetQuestObjectives(questID)
	if type(list) ~= "table" then return nil end
	local parts = {}
	for i, objective in ipairs(list) do
		if not (readable(objective.numFulfilled) and readable(objective.finished)) then return nil end
		parts[i] = tostring(objective.numFulfilled) .. (objective.finished and "+" or "-")
	end
	local complete = C_QuestLog.IsComplete(questID)
	if not readable(complete) then return nil end
	return (complete and "c" or "o") .. table.concat(parts, ","), #list
end

-- Walks the log for objective progress, quests that became complete and quests whose area you
-- entered, then applies the order. A quest seen for the first time (after a login or reload, or
-- when its objectives arrive late) is recorded without counting as activity.
function QuestRank.Sweep()
	if not QuestRank.db.rank then return end
	local state = character()
	noticeWatchChanges(state)
	local entered = {}
	for _, info in ipairs(logQuests()) do
		local id = info.questID
		local sig, count = objectives(id)
		local onMap = readable(info.isOnMap) and info.isOnMap == true
		local before = snapshots[id]
		if before then
			if sig and before.sig and sig ~= before.sig and not (before.count == 0 and count > 0) then
				bump(state, id)
			end
			if onMap and before.onMap == false then entered[#entered + 1] = id end
		end
		snapshots[id] = { sig = sig or (before and before.sig), count = count or (before and before.count),
			onMap = onMap }
	end
	-- Quests whose area you walked into: the nearest ends on top.
	local distance = {}
	if C_QuestLog.GetDistanceSqToQuest then
		for _, id in ipairs(entered) do
			local d = C_QuestLog.GetDistanceSqToQuest(id)
			distance[id] = readable(d) and d or math.huge
		end
	end
	table.sort(entered, function(a, b)
		local da, db = distance[a] or 0, distance[b] or 0
		if da ~= db then return da > db end
		return a < b
	end)
	for _, id in ipairs(entered) do bump(state, id) end
	QuestRank.Apply()
end

local function sweepSoon()
	Everlook.Schedule.Defer("EverlookQuestRank", QuestRank.Sweep)
end

-- Alt-click pins: a button of our own over each quest title, taking clicks only while Alt is held,
-- so the game's own click (open the quest map) doesn't run as well.
local overlays = {} -- [tracker block] = our button
local modules = {} -- tracker modules we hooked, in order
local refreshPending = false

local function pinned(questID)
	return questID and pinIndex(character(), questID) ~= nil
end

function QuestRank.TogglePin(questID)
	if type(questID) ~= "number" then return end
	local state = character()
	if pinIndex(state, questID) then
		unpin(state, questID)
	else
		state.pins[#state.pins + 1] = questID
	end
	bump(state, questID)
	QuestRank.RefreshAll()
	sweepSoon()
end

local function showTooltip(self)
	local id = self.block and self.block.id
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(pinned(id) and "Alt-click: unpin" or "Alt-click: pin to the top", 1, 1, 1)
	GameTooltip:Show()
end

local function overlayFor(block)
	local overlay = overlays[block]
	if overlay then return overlay end
	local header = block.HeaderButton
	if not header or InCombatLockdown() then return nil end
	overlay = CreateFrame("Button", nil, block)
	overlay:SetAllPoints(header)
	overlay:SetFrameLevel(header:GetFrameLevel() + 2)
	overlay:RegisterForClicks("LeftButtonUp")
	overlay.mark = overlay:CreateTexture(nil, "OVERLAY")
	overlay.mark:SetTexture(LOGO)
	overlay.mark:SetSize(12, 12)
	overlay.mark:SetPoint("RIGHT", overlay, "RIGHT", 0, 0)
	-- The block is pooled and may show another quest by now: read its id at click time.
	overlay:SetScript("OnClick", function(self) QuestRank.TogglePin(self.block.id) end)
	overlay:SetScript("OnEnter", showTooltip)
	overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
	overlay.block = block
	overlays[block] = overlay
	return overlay
end

function QuestRank.Refresh(module)
	for _, overlay in pairs(overlays) do
		if overlay.module == module then
			overlay:Hide()
			overlay.module = nil
		end
	end
	if not (QuestRank.db.rank and QuestRank.db.rank_pin) then return end
	local alt = IsAltKeyDown()
	module:EnumerateActiveBlocks(function(block)
		if block.template ~= module.blockTemplate or type(block.id) ~= "number" then return end
		local overlay = overlayFor(block)
		if not overlay then
			refreshPending = true
			return
		end
		overlay.module = module
		overlay.mark:SetShown(pinned(block.id))
		overlay:EnableMouse(alt)
		overlay:Show()
	end)
end

function QuestRank.RefreshAll()
	refreshPending = false
	for _, module in ipairs(modules) do QuestRank.Refresh(module) end
end

local function hook(module)
	if not (module and module.EndLayout and module.EnumerateActiveBlocks) then return end
	modules[#modules + 1] = module
	hooksecurefunc(module, "EndLayout", function(self) QuestRank.Refresh(self) end)
end

local EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
	"QUEST_REMOVED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_ENABLED", "MODIFIER_STATE_CHANGED",
}

function QuestRank:Start()
	for _, event in ipairs(EVENTS) do self:RegisterEvent(event) end
	local super = C_SuperTrack.GetSuperTrackedQuestID()
	lastSuper = readable(super) and super or nil
	lastSet = asSet(watches())
	-- After a login or reload the top is taken as followed already, so a super-track you cleared
	-- or changed holds until a new quest reaches the top.
	followed = watches()[1]
	QuestRank.RefreshAll()
	sweepSoon()
end

-- Gives the order back to the game; every watch stays as it is.
function QuestRank:Stop()
	for _, event in ipairs(EVENTS) do self:UnregisterEvent(event) end
	snapshots, lastSet, pending, refused, followed = {}, nil, false, nil, nil
	C_QuestLog.SortQuestWatches()
	QuestRank.RefreshAll()
end

function QuestRank:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Quests")
	page:Checkbox("rank", "Rank the quest tracker",
		"Keeps the quests you're working on at the top of the quest tracker. A quest you make progress on, finish, super-track or walk into the area of moves to the top and is tracked; when the tracker is full, the quest with the oldest activity is untracked. A quest you untrack yourself comes back on its next activity. Waits for combat to end and while you hold Shift. Turning it off gives the order back to the game.")
	page:Checkbox("rank_pin", "Alt-click to pin",
		"Alt-click a quest's title in the tracker to pin it above every other quest; Alt-click it again to unpin. Pinned quests show the Everlook mark. Needs Rank the quest tracker to be on.")
	page:Checkbox("rank_follow", "Follow the top quest",
		"Super-tracks the quest at the top of the tracker, so the map arrow and waypoint lead to it. It changes each time a new quest reaches the top; a quest you super-track yourself holds until then, and a map pin or waypoint you set is left alone. Waits for combat to end and while you hold Shift. Turning it off leaves the quest super-tracked as it is. Needs Rank the quest tracker to be on.")
end

function QuestRank:OnEnable()
	hook(QuestObjectiveTracker)
	hook(CampaignQuestObjectiveTracker)
	if self.db.rank then self:Start() end
end

function QuestRank:OnSettingChanged(key, value)
	if key == "rank" then
		if value then self:Start() else self:Stop() end
	elseif key == "rank_pin" and self.db.rank then
		QuestRank.RefreshAll()
		sweepSoon()
	elseif key == "rank_follow" and self.db.rank then
		followed = nil
		sweepSoon()
	end
end

function QuestRank:QUEST_LOG_UPDATE() sweepSoon() end
function QuestRank:QUEST_WATCH_UPDATE() sweepSoon() end
function QuestRank:ZONE_CHANGED() sweepSoon() end
function QuestRank:ZONE_CHANGED_NEW_AREA() sweepSoon() end

function QuestRank:QUEST_WATCH_LIST_CHANGED() sweepSoon() end

function QuestRank:QUEST_ACCEPTED(_, questID)
	if type(questID) == "number" then bump(character(), questID) end
	sweepSoon()
end

function QuestRank:QUEST_REMOVED(_, questID)
	if type(questID) ~= "number" then return end
	local state = character()
	state.activity[questID] = nil
	unpin(state, questID)
	snapshots[questID] = nil
	sweepSoon()
end

function QuestRank:SUPER_TRACKING_CHANGED()
	local id = C_SuperTrack.GetSuperTrackedQuestID()
	if not readable(id) then return end
	if type(id) == "number" and id > 0 and id ~= lastSuper then bump(character(), id) end
	lastSuper = id
	sweepSoon()
end

function QuestRank:PLAYER_REGEN_ENABLED()
	if refreshPending then QuestRank.RefreshAll() end
	if pending then sweepSoon() end
end

function QuestRank:MODIFIER_STATE_CHANGED(_, key, down)
	if key == "LALT" or key == "RALT" then
		local alt = down == 1
		for _, overlay in pairs(overlays) do
			if overlay.module then overlay:EnableMouse(alt) end
		end
	elseif (key == "LSHIFT" or key == "RSHIFT") and down == 0 and pending then
		sweepSoon()
	end
end

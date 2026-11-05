-- Settings saved under the old name, EverlookQuickQuest, move across. EverlookDB is loaded by now:
-- Everlook's ADDON_LOADED came before this file ran.
if EverlookDB and EverlookDB.EverlookQuickQuest and not EverlookDB.EverlookAutoQuest then
	EverlookDB.EverlookAutoQuest, EverlookDB.EverlookQuickQuest = EverlookDB.EverlookQuickQuest, nil
end

local AutoQuest = Everlook:NewAddon("EverlookAutoQuest", {
	label = "Auto Quest",
	defaults = {
		accept = true,
		turnIn = true,
		skipTrivial = true,
		acceptRepeatable = false,
		turnInRepeatable = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookAutoQuest", {
	"C_GossipInfo.GetActiveQuests",
	"C_GossipInfo.GetAvailableQuests",
	"C_GossipInfo.SelectActiveQuest",
	"C_GossipInfo.SelectAvailableQuest",
	"GetNumActiveQuests",
	"GetActiveTitle",
	"GetActiveQuestID",
	"SelectActiveQuest",
	"GetNumAvailableQuests",
	"GetAvailableQuestInfo",
	"SelectAvailableQuest",
	"C_QuestLog.IsRepeatableQuest",
	"C_QuestLog.IsQuestTrivial",
	"GetQuestID",
	"QuestFlagsPVP",
	"QuestGetAutoAccept",
	"AcknowledgeAutoAcceptQuest",
	"AcceptQuest",
	"ConfirmAcceptQuest",
	"StaticPopup_Hide",
	"IsQuestCompletable",
	"GetQuestMoneyToGet",
	"CompleteQuest",
	"GetNumQuestChoices",
	"GetQuestReward",
	"GetQuestItemLink",
	"GetQuestItemInfo",
	"C_Item.GetItemInfo",
	"QuestInfoFrame.rewardsFrame",
	"QuestInfo_GetRewardButton",
	"C_Timer.After",
	"InCombatLockdown",
	"IsShiftKeyDown",
})

function AutoQuest:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Quests")
	page:Checkbox("accept", "Auto accept", "Accept quests automatically. Hold Shift to pause.")
	page:Checkbox("turnIn", "Auto turn in",
		"Turn in completed quests automatically. Quests with a reward choice are left to you. Hold Shift to pause.")
	page:Checkbox("skipTrivial", "Skip gray quests", "Don't auto accept quests too low level to give experience.")
	page:Checkbox("acceptRepeatable", "Accept repeatable quests",
		"Also accept daily and other repeatable quests. Needs Auto accept.")
	page:Checkbox("turnInRepeatable", "Turn in repeatable quests",
		"Also turn in daily and other repeatable quests. Needs Auto turn in.")
end

function AutoQuest:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_GREETING")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_ACCEPT_CONFIRM")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("QUEST_FINISHED")
end

-- Shift pauses; combat, or a client that can't report combat, holds everything back.
local function paused()
	return IsShiftKeyDown() or not InCombatLockdown or InCombatLockdown()
end

-- true/false, or nil when the client can't say.
local function isRepeatable(questID)
	if questID and C_QuestLog and C_QuestLog.IsRepeatableQuest then
		return C_QuestLog.IsRepeatableQuest(questID) == true
	end
	return nil
end

-- A quest is ours to handle when it's known not to be repeatable, or repeatables are allowed.
local function allowed(repeatable, option)
	return repeatable == false or option == true
end

-- Daily and weekly quests carry a frequency instead of the repeatable flag.
local function periodic(frequency)
	return type(frequency) == "number" and frequency ~= 0
end

local function gossipRepeatable(quest)
	if periodic(quest.frequency) or quest.repeatable == true then return true end
	if quest.repeatable == false then return false end
	return isRepeatable(quest.questID)
end

-- A cost the client can't report counts as a cost.
local function costsMoney()
	return not GetQuestMoneyToGet or GetQuestMoneyToGet() > 0
end

-- Gossip window: turn in one completed quest, else pick up one offered quest.
-- The window refreshes after each step, so this works through them one by one.
function AutoQuest:GOSSIP_SHOW()
	if paused() then return end
	local db = self.db
	if db.turnIn then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
			if quest.isComplete and allowed(gossipRepeatable(quest), db.turnInRepeatable) then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if db.accept then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
			if not quest.isIgnored and not (db.skipTrivial and quest.isTrivial)
				and allowed(gossipRepeatable(quest), db.acceptRepeatable) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
end

-- Older quest-list window, same rules as gossip.
function AutoQuest:QUEST_GREETING()
	if paused() then return end
	local db = self.db
	if db.turnIn then
		for i = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(i)
			local repeatable = GetActiveQuestID and isRepeatable(GetActiveQuestID(i))
			if isComplete and allowed(repeatable, db.turnInRepeatable) then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if db.accept then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial, frequency, repeatable = GetAvailableQuestInfo(i)
			if periodic(frequency) then
				repeatable = true
			elseif type(repeatable) ~= "boolean" then
				repeatable = nil
			end
			if not (db.skipTrivial and isTrivial) and allowed(repeatable, db.acceptRepeatable) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

function AutoQuest:QUEST_DETAIL()
	if paused() or not self.db.accept then return end
	if not allowed(isRepeatable(GetQuestID()), self.db.acceptRepeatable) then return end
	-- A PvP flag the client can't report counts as PvP.
	if not QuestFlagsPVP or QuestFlagsPVP() then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
		return
	end
	if self.db.skipTrivial and (not C_QuestLog.IsQuestTrivial or C_QuestLog.IsQuestTrivial(GetQuestID())) then return end
	AcceptQuest()
end

-- Escort and shared quests ask for confirmation.
function AutoQuest:QUEST_ACCEPT_CONFIRM()
	if paused() or not self.db.accept then return end
	ConfirmAcceptQuest()
	StaticPopup_Hide("QUEST_ACCEPT")
end

function AutoQuest:QUEST_PROGRESS()
	if paused() or not self.db.turnIn then return end
	if not allowed(isRepeatable(GetQuestID()), self.db.turnInRepeatable) then return end
	if IsQuestCompletable() and not costsMoney() then
		CompleteQuest()
	end
end

-- Coin icon on the reward choice that sells for the most.
local marker

local function hideMarker()
	if marker then marker:Hide() end
end

local function markBestReward()
	local best, bestValue = nil, 0
	for i = 1, GetNumQuestChoices() do
		local link = GetQuestItemLink("choice", i)
		local _, _, count = GetQuestItemInfo("choice", i)
		local sellPrice = link and select(11, C_Item.GetItemInfo(link))
		local value = (sellPrice or 0) * math.max(count or 1, 1)
		if value > bestValue then
			best, bestValue = i, value
		end
	end

	local button = best and QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, best)
	if not button then return end

	if not marker then
		marker = UIParent:CreateTexture(nil, "OVERLAY")
		marker:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
		marker:SetSize(16, 16)
	end
	marker:SetParent(button)
	marker:SetDrawLayer("OVERLAY", 7)
	marker:ClearAllPoints()
	marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
	marker:Show()
end

function AutoQuest:QUEST_COMPLETE()
	hideMarker()
	local numChoices = GetNumQuestChoices()
	if numChoices > 1 then
		-- Let the quest frame lay out its reward buttons first.
		C_Timer.After(0, markBestReward)
		return
	end
	if paused() or not self.db.turnIn or costsMoney() then return end
	if not allowed(isRepeatable(GetQuestID()), self.db.turnInRepeatable) then return end
	GetQuestReward(numChoices)
end

function AutoQuest:QUEST_FINISHED()
	hideMarker()
end

local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookAutoQuest")

local gossipActive, gossipAvailable = {}, {}
C_GossipInfo = {
	GetActiveQuests = function() return gossipActive end,
	GetAvailableQuests = function() return gossipAvailable end,
	SelectActiveQuest = function(id) t.log("turnin " .. id) end,
	SelectAvailableQuest = function(id) t.log("accept " .. id) end,
}

local greetingActive, greetingAvailable = {}, {}
GetNumActiveQuests = function() return #greetingActive end
GetActiveTitle = function(i) return "title", greetingActive[i].complete end
GetActiveQuestID = function(i) return greetingActive[i].id end
SelectActiveQuest = function(i) t.log("greeting turnin " .. i) end
GetNumAvailableQuests = function() return #greetingAvailable end
GetAvailableQuestInfo = function(i)
	local quest = greetingAvailable[i]
	return quest.trivial, quest.frequency or 0, quest.repeatable
end
SelectAvailableQuest = function(i) t.log("greeting accept " .. i) end

local repeatables = {}
C_QuestLog = {
	IsRepeatableQuest = function(id) return repeatables[id] == true end,
	IsQuestTrivial = function() return false end,
}
local questID, pvp, money = 9, false, 0
GetQuestID = function() return questID end
QuestFlagsPVP = function() return pvp end
QuestGetAutoAccept = function() return false end
AcknowledgeAutoAcceptQuest = function() t.log("acknowledge") end
AcceptQuest = function() t.log("AcceptQuest") end
ConfirmAcceptQuest = function() t.log("ConfirmAcceptQuest") end
StaticPopup_Hide = function() end
IsQuestCompletable = function() return true end
GetQuestMoneyToGet = function() return money end
CompleteQuest = function() t.log("CompleteQuest") end

local choices = { 1 }
GetNumQuestChoices = function() return #choices end
GetQuestReward = function(n) t.log("reward " .. n) end
GetQuestItemLink = function(_, i) return "item" .. i end
GetQuestItemInfo = function() return "name", "icon", 1 end
C_Item = {
	GetItemInfo = function(link)
		local prices = { item1 = 5, item2 = 50, item3 = 10 }
		return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[link]
	end,
}
QuestInfoFrame = { rewardsFrame = {} }
QuestInfo_GetRewardButton = function(_, i) t.log("button " .. i) return {} end
UIParent = {
	CreateTexture = function()
		return setmetatable({}, { __index = function(_, method)
			return function() if method == "Show" then t.log("coin shown") end end
		end })
	end,
}

-- Settings saved under the old name carry over.
EverlookDB.EverlookQuickQuest = { accept = false, turnIn = true }
t.load("EverlookAutoQuest")
t.fire("PLAYER_LOGIN")
local QQ = Everlook:GetAddon("EverlookAutoQuest")
local function fire(...) t.reset() t.fire(...) end

check(QQ.db.accept == false and EverlookDB.EverlookQuickQuest == nil and EverlookDB.EverlookAutoQuest == QQ.db,
	"settings saved as QuickQuest move to Auto Quest")
QQ.db.accept = true
check(QQ.db.accept and QQ.db.turnIn and QQ.db.skipTrivial, "accept, turn in and skip gray start on")
check(not QQ.db.acceptRepeatable and not QQ.db.turnInRepeatable, "repeatable options start off")

-- Gossip
gossipActive = {
	{ questID = 1, isComplete = true, repeatable = true },
	{ questID = 2, isComplete = true, repeatable = false },
}
fire("GOSSIP_SHOW")
check(has("turnin 2") and not has("turnin 1"), "gossip: turns in, skips repeatable")

QQ.db.turnInRepeatable = true
fire("GOSSIP_SHOW")
check(has("turnin 1"), "gossip: turns in repeatable when allowed")
QQ.db.turnInRepeatable = false

gossipActive = {}
gossipAvailable = { { questID = 3, isIgnored = true }, { questID = 4 }, { questID = 5, isTrivial = true }, { questID = 6 } }
repeatables[4] = true
fire("GOSSIP_SHOW")
check(has("accept 6") and #t.calls == 1, "gossip: skips ignored, repeatable and gray")

gossipAvailable = { { questID = 7, frequency = 1, repeatable = false }, { questID = 8 } }
fire("GOSSIP_SHOW")
check(has("accept 8") and #t.calls == 1, "gossip: daily counts as repeatable")

-- Greeting
greetingActive = { { id = 20, complete = false }, { id = 21, complete = true } }
fire("QUEST_GREETING")
check(has("greeting turnin 2"), "greeting: turns in the completed quest")

greetingActive = {}
greetingAvailable = { { trivial = true, repeatable = false }, { frequency = 2, repeatable = false }, { repeatable = false } }
fire("QUEST_GREETING")
check(has("greeting accept 3") and #t.calls == 1, "greeting: skips gray and weekly")

-- Pauses
t.shift = true
fire("GOSSIP_SHOW"); t.fire("QUEST_DETAIL")
check(#t.calls == 0, "Shift pauses")
t.shift = false

t.combat = true
fire("GOSSIP_SHOW"); t.fire("QUEST_DETAIL")
check(#t.calls == 0, "combat holds back")
t.combat = false

-- Quest windows
fire("QUEST_DETAIL")
check(has("AcceptQuest"), "detail: accepts")

pvp = true
fire("QUEST_DETAIL")
check(#t.calls == 0, "detail: skips PvP")
pvp = false

repeatables[9] = true
fire("QUEST_DETAIL"); t.fire("QUEST_PROGRESS"); t.fire("QUEST_COMPLETE")
check(#t.calls == 0, "repeatable quest is left on every window")
repeatables[9] = nil

local isRepeatable = C_QuestLog.IsRepeatableQuest
C_QuestLog.IsRepeatableQuest = nil
fire("QUEST_DETAIL")
check(#t.calls == 0, "unknown repeatable state fails closed")
C_QuestLog.IsRepeatableQuest = isRepeatable

fire("QUEST_ACCEPT_CONFIRM")
check(has("ConfirmAcceptQuest"), "confirms escort and shared quests")

fire("QUEST_PROGRESS")
check(has("CompleteQuest"), "progress: completes")

money = 100
fire("QUEST_PROGRESS"); t.fire("QUEST_COMPLETE")
check(#t.calls == 0, "a turn-in that costs gold is left")
money = 0

fire("QUEST_COMPLETE")
check(has("reward 1"), "single reward is taken")

choices = { 1, 2, 3 }
fire("QUEST_COMPLETE")
check(has("button 2") and has("coin shown") and not t.printed("reward"), "choice of rewards: coin on the best, nothing taken")

t.done()

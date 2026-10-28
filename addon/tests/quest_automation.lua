-- Quest automation: when a gossip window, a greeting, the quest detail, or the turn-in window opens, this accepts or turns in the quest if the matching choice below is on.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local accepted, rewards = 0, {}
	env.AcceptQuest = function() accepted = accepted + 1 end
	-- Only names that appear in Blizzard's own code: the quest frame asks
	-- GetQuestMoneyToGet, QuestFlagsPVP and C_QuestLog.IsRepeatableQuest(GetQuestID()).
	env.GetQuestID = function() return 1 end
	env.QuestFlagsPVP = function() return false end
	env.GetQuestMoneyToGet = function() return 0 end
	env.C_QuestLog = { IsRepeatableQuest = function() return false end }
	env.GetNumQuestChoices = function() return 2 end
	env.GetQuestReward = function(choice) rewards[#rewards + 1] = choice end
	event("QUEST_DETAIL")
	check("disabled quest automation does nothing", accepted == 0)
	addon.module.set("quest_automation", "enabled", true)
	event("QUEST_DETAIL")
	event("QUEST_COMPLETE")
	check("quest automation accepts quests", accepted == 1)
	check("quest automation preserves reward choice", #rewards == 0)
	env.GetNumQuestChoices = function() return 1 end
	event("QUEST_COMPLETE")
	check("quest automation takes a sole reward", rewards[1] == 1)
	env.IsShiftKeyDown = function() return true end
	event("QUEST_DETAIL")
	check("Shift pauses automation", accepted == 1)
	env.IsShiftKeyDown = function() return false end
	env.GetQuestMoneyToGet = function() return 100 end
	event("QUEST_COMPLETE")
	check("paid quest turn-ins remain manual", #rewards == 1)
	env.GetQuestMoneyToGet = nil
	event("QUEST_COMPLETE")
	check("a quest whose cost is unknown stays manual", #rewards == 1)
	env.GetQuestMoneyToGet = function() return 0 end
	event("QUEST_COMPLETE")
	check("a free quest is turned in again once the cost is known", #rewards == 2)

	env.C_QuestLog.IsRepeatableQuest = function() return true end
	event("QUEST_DETAIL")
	check("repeatable quests require opt-in", accepted == 1)
	addon.module.set("quest_automation", "repeatable", true)
	event("QUEST_DETAIL")
	check("repeatable quests are accepted with the opt-in", accepted == 2)
	addon.module.set("quest_automation", "repeatable", false)
	env.C_QuestLog = nil
	event("QUEST_DETAIL")
	check("a quest that cannot be classified stays manual", accepted == 2)
	env.C_QuestLog = { IsRepeatableQuest = function() return false end }
	do
		local before = accepted
		env.QuestFlagsPVP = function() return true end
		event("QUEST_DETAIL")
		check("a quest that flags the player for PvP is left to the player", accepted == before)
		env.QuestFlagsPVP = function() return false end
		event("QUEST_DETAIL")
		check("a quest that does not flag PvP is accepted", accepted == before + 1)
		env.QuestFlagsPVP = nil
		event("QUEST_DETAIL")
		check("a quest whose PvP flag the client cannot report stays manual", accepted == before + 1)
		env.QuestFlagsPVP = function() return false end
		local combat = env.InCombatLockdown
		env.InCombatLockdown = nil
		event("QUEST_DETAIL")
		check("a quest stays manual when the client cannot say whether you are in combat", accepted == before + 1)
		env.InCombatLockdown = combat
	end
end

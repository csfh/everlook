-- Quest automation: when a gossip window, a greeting, the quest detail, or the turn-in window opens, this accepts or turns in the quest if the matching choice below is on.
return function(check, lib)
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
	do
		-- What quest automation decides at each window, from the facts alone, and why it does nothing when it does nothing.
		local source = lib.source
		local Everlook = { module = { register = function() end, get = function() return false end, paused = function() return false end } }
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.Everlook = Everlook
		local chunk = assert(loadfile(source("quest_automation")))
		setfenv(chunk, env)
		chunk("Everlook_QuestAutomation", Everlook)
		local decide = Everlook.quest_automation.decide

		local function facts(event, extra)
			local base = { event = event, options = { accept = true, turn_in = true, repeatable = false } }
			for key, value in pairs(extra or {}) do base[key] = value end
			return base
		end
		local function says(expected_action, expected_argument, expected_reason, f)
			local action, argument, reason = decide(f)
			return action == expected_action and argument == expected_argument and reason == expected_reason
		end

		check("Shift holds automation back", says(nil, nil, "paused", facts("QUEST_DETAIL", { paused = true })))
		check("combat holds automation back", says(nil, nil, "combat", facts("QUEST_DETAIL", { in_combat = true })))

		local gossip = { active = { { questID = 1, isComplete = false }, { questID = 2, isComplete = true, repeatable = true }, { questID = 3, isComplete = true } },
			available = { { questID = 4, isIgnored = true }, { questID = 5, repeatable = true }, { questID = 6 } } }
		check("a completed quest is picked before an available one, skipping a repeatable one by default",
			says("select_active_gossip", 3, nil, facts("GOSSIP_SHOW", { gossip = gossip })))
		check("a repeatable quest is picked when repeatable quests are included",
			says("select_active_gossip", 2, nil, facts("GOSSIP_SHOW", { gossip = gossip, options = { accept = true, turn_in = true, repeatable = true } })))
		check("with turning in off the first available quest that is not ignored or repeatable is picked",
			says("select_available_gossip", 6, nil, facts("GOSSIP_SHOW", { gossip = gossip, options = { accept = true, turn_in = false, repeatable = false } })))
		check("with both off nothing is picked", says(nil, nil, "nothing to pick", facts("GOSSIP_SHOW", { gossip = gossip, options = { accept = false, turn_in = false, repeatable = false } })))
		check("no gossip list means nothing to do", says(nil, nil, "no gossip list", facts("GOSSIP_SHOW")))

		check("a greeting opens its first completed quest", says("select_active_greeting", 2, nil, facts("QUEST_GREETING", { greeting = { active = { false, true }, available = 3 } })))
		check("a greeting opens an available quest when none is complete", says("select_available_greeting", 1, nil, facts("QUEST_GREETING", { greeting = { active = { false }, available = 1 } })))

		check("a repeatable quest the player did not include is left alone at the detail window", says(nil, nil, "repeatable", facts("QUEST_DETAIL", { repeatable_blocked = true, can_accept = true })))
		check("the detail window accepts", says("accept", nil, nil, facts("QUEST_DETAIL", { can_accept = true })))
		check("a quest that flags PvP is left to the player", says(nil, nil, "pvp", facts("QUEST_DETAIL", { can_accept = true, pvp = true })))
		check("an auto-accepted quest is acknowledged", says("acknowledge", nil, nil, facts("QUEST_DETAIL", { can_accept = true, auto_accept = true, can_acknowledge = true })))
		check("an auto-accepted quest with no way to acknowledge is left alone", says(nil, nil, "auto-accepted", facts("QUEST_DETAIL", { can_accept = true, auto_accept = true })))
		check("a client that cannot accept does nothing", says(nil, nil, "accepting is off", facts("QUEST_DETAIL", { can_accept = false })))

		check("the progress window completes a completable quest", says("complete", nil, nil, facts("QUEST_PROGRESS", { completable = true })))
		check("a turn-in that costs money stays for the player", says(nil, nil, "turning in is off or costs money", facts("QUEST_PROGRESS", { completable = true, costs_money = true })))
		check("a quest that is not complete is left alone", says(nil, nil, "not complete", facts("QUEST_PROGRESS", { completable = false })))

		check("a sole reward is taken", says("reward", 1, nil, facts("QUEST_COMPLETE", { choices = 1 })))
		check("a quest with no reward choice is turned in", says("reward", 0, nil, facts("QUEST_COMPLETE", { choices = 0 })))
		check("a choice between rewards stays for the player", says(nil, nil, "choice of rewards", facts("QUEST_COMPLETE", { choices = 2 })))
		check("an unknown reward count stays for the player", says(nil, nil, "turning in is off, costs money or has no count", facts("QUEST_COMPLETE", {})))
		check("any other event is not a quest window", says(nil, nil, "not a quest window", facts("SOMETHING_ELSE")))
	end
end

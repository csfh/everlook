-- Quest text size: sets the quest description, objectives, reward, and progress text to the size you choose, and waits while you are in combat.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon2, env2, event2, hooks, tickers, frames = load_all()
	-- A font object the way the game's quest text font answers, as the Fonts tests build one.
	local font = { path = "original.ttf", size = 12, flags = "OUTLINE" }
	function font:GetObjectType() return "Font" end
	function font:GetFont() return self.path, self.size, self.flags end
	function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
	env2.QuestInfoDescriptionText = font
	local cvar_calls = 0
	env2.C_CVar = {
		GetCVar = function() cvar_calls = cvar_calls + 1 end,
		SetCVar = function() cvar_calls = cvar_calls + 1 end,
	}
	addon2.module.set("quest_text_size", "enabled", true)
	check("quest interface enlarges quest text without a console variable", font.size == 16 and cvar_calls == 0)
	addon2.module.set("quest_text_size", "enabled", false)
	check("quest interface restores the previous text size", font.size == 12 and cvar_calls == 0)

	do
		-- The "at once" option sets the game's own variable where there is one, and puts the player's value back.
		local values = { instantQuestText = "0" }
		local sets = {}
		env2.GetCVar = function(name) return values[name] end
		env2.SetCVar = function(name, value) sets[#sets + 1] = name .. "=" .. value; values[name] = value end
		env2.EverlookSaved = env2.EverlookSaved or {}
		addon2.module.set("quest_text_size", "enabled", true)
		check("the at once option is off by default and the variable is left alone", #sets == 0 and values.instantQuestText == "0")
		addon2.module.set("quest_text_size", "instant_text", true)
		check("turned on, it sets the variable and keeps the player's value", values.instantQuestText == "1" and env2.EverlookSaved.quest_text_size_before == "0")
		addon2.module.set("quest_text_size", "enabled", false)
		check("turning the module off puts the player's value back and forgets it", values.instantQuestText == "0" and env2.EverlookSaved.quest_text_size_before == nil)
		addon2.module.set("quest_text_size", "enabled", true)
		values.instantQuestText = "1"
		addon2.module.set("quest_text_size", "instant_text", false)
		check("turning the option off puts the saved value back", values.instantQuestText == "0")
		values.instantQuestText = nil
		local before = #sets
		addon2.module.set("quest_text_size", "instant_text", true)
		check("a client with no such variable is left alone", #sets == before and env2.EverlookSaved.quest_text_size_before == nil)
		addon2.module.set("quest_text_size", "instant_text", false)
		addon2.module.set("quest_text_size", "enabled", false)
		env2.GetCVar, env2.SetCVar = nil, nil
	end
end

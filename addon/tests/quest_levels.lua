-- Quest levels: puts the level in brackets in front of a quest title on the quest log list, using the game's own quest level.
return function(check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "quest_levels" })
	-- Quest levels: the level goes on the quest log list after the game has drawn it, and nothing of the game's is replaced.
	local function region(initial)
		local r = { text = initial, height = #initial > 25 and 28 or 14 }
		function r:GetText() return self.text end
		function r:SetText(value) self.text = value; self.height = #value > 25 and 28 or 14 end
		function r:GetHeight() return self.height end
		return r
	end
	local function log_button(quest_id, text)
		local b = { questID = quest_id, Text = region(text), height = 30 }
		function b:GetHeight() return self.height end
		function b:SetHeight(value) self.height = value end
		return b
	end
	local first, second, third = log_button(1, "Wolves"), log_button(2, "[2] Murloc Menace"), log_button(3, "A Quite Long Quest Title")
	local dirty = 0
	play.QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
		local list, index = { first, second, third }, 0
		return function() index = index + 1; return list[index], true end
	end }, Contents = { MarkDirty = function() dirty = dirty + 1 end } }
	local gets_title = function() return "untouched" end
	play.C_QuestLog = { GetTitleForQuestID = gets_title, GetQuestDifficultyLevel = function(quest_id) return quest_id == 3 and 9 or 8 end }
	local hooks = {}
	play.hooksecurefunc = function(name, fn) hooks[#hooks + 1] = { name = name, fn = fn } end
	play.QuestLogQuests_Update = function() end
	addon.module.set("quest_levels", "enabled", true)
	check("the quest log list is hooked once, by name, after the game draws it", #hooks == 1 and hooks[1].name == "QuestLogQuests_Update")
	check("a quest title gains its level", first.Text:GetText() == "[8] Wolves")
	check("a title that already starts with a bracketed number is left alone", second.Text:GetText() == "[2] Murloc Menace")
	check("a button grows when the longer title needs another line", third.Text:GetText() == "[9] A Quite Long Quest Title" and third.height == 44 and dirty >= 1)
	check("the lookup the game and the tracker call is not replaced", play.C_QuestLog.GetTitleForQuestID == gets_title)
	first.Text:SetText("Wolves")
	hooks[1].fn()
	check("a list the game draws again is decorated again", first.Text:GetText() == "[8] Wolves")
	hooks[1].fn()
	check("a title already decorated is not decorated twice", first.Text:GetText() == "[8] Wolves")
	play.issecretvalue = function(value) return value == "secret" end
	first.Text:SetText("secret")
	hooks[1].fn()
	check("a secret title is left as it is", first.Text:GetText() == "secret")
	play.issecretvalue = nil
	first.Text:SetText("Wolves of the North")
	addon.module.set("quest_levels", "enabled", false)
	check("turning quest levels off puts back the text it changed", third.Text:GetText() == "A Quite Long Quest Title" and third.height == 30)
	check("and leaves a text the game has written since", first.Text:GetText() == "Wolves of the North" and second.Text:GetText() == "[2] Murloc Menace")
	hooks[1].fn()
	check("a list drawn while it is off is not decorated", third.Text:GetText() == "A Quite Long Quest Title")
	play.QuestScrollFrame, play.hooksecurefunc, play.QuestLogQuests_Update = nil, nil, nil
	play.C_QuestLog = { GetTitleForQuestID = function() return "Wolves" end }
	check("a client without the quest log list is left alone", pcall(addon.module.set, "quest_levels", "enabled", true))
	addon.module.set("quest_levels", "enabled", false)
	play.C_QuestLog.GetTitleForQuestID = function() return "Wolves" end
	local title = "Wolves"
end

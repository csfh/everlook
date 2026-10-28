-- Island recap: sums up quests, experience, money and time every 30 minutes.
return function(_, check, lib)
	local read_source, island_world, quest_world, secret_stat, notice_key = lib.read_source, lib.island_world, lib.quest_world, lib.secret_stat, lib.notice_key
	local function show_recap(addon, env)
		local buttons = {}
		env.CreateSettingsButtonInitializer = function(name, _, click)
			return { name = name, click = click }
		end
		local module
		for _, candidate in ipairs(addon.module.modules) do
			if candidate.id == "island" then module = candidate end
		end
		local layout = { AddInitializer = function(_, row) buttons[row.name] = row end }
		for _, section in ipairs(addon.module.sections(module) or {}) do
			if section.after then section.after(layout) end
		end
		return buttons["Session recap"] and buttons["Session recap"].click()
	end

	check("recap experience uses the shared bar advance",
		not read_source("island_recap.lua"):find("xp_level + 1", 1, true))
	check("the level cap stays behind the shared readings",
		not read_source("island_recap.lua"):find("GetMaxPlayerLevel", 1, true)
		and not read_source("island_experience.lua"):find("GetMaxPlayerLevel", 1, true))
	do
		local addon, env, event = quest_world()
		addon.module.set("island", "source_quest_completion", true)
		addon.module.set("island", "feed_recap", true)
		event("QUEST_TURNED_IN", 23, 10, 50)
		local completed = 0
		for _, notice in ipairs(addon.island.view().notices) do
			if notice.text == "Quest completed" then completed = completed + 1 end
		end
		local completion = nil
		for _, notice in ipairs(addon.island.view().notices) do
			if notice.text == "Quest completed" then completion = notice end
		end
		check("one turn-in publishes one completion notice", completed == 1 and completion.detail == "Ready to return" and completion.money == 50)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		event("QUEST_TURNED_IN", secret, 10, 50)
		completed = 0
		for _, notice in ipairs(addon.island.view().notices) do
			if notice.text == "Quest completed" then completed = completed + 1 end
		end
		check("a secret turn-in does not add a completion notice", completed == 1)
		check("show recap counts that turn-in once", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("Quests completed: 1", 1, true))
	end
	do
		local addon, env, event, state, _, tickers = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_recap", true)
		state.level = 14
		tickers[1].callback()
		check("a missed level marks experience incomplete", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("XP incomplete", 1, true))
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		event("QUEST_TURNED_IN", secret)
		event("QUEST_TURNED_IN", 18)
		env.GetMoney = function() return secret end
		show_recap(addon, env)
		local recap = notice_key(addon, "session-recap")
		check("secret quests and money stay out of the recap", recap.detail:find("Quests completed: 1", 1, true)
			and recap.detail:find("Money unavailable", 1, true) and recap.money == nil)
	end
	do
		local addon, env, _, state = island_world()
		state.level, state.xp, state.xp_max = 90, 0, 0
		env.GetMaxPlayerLevel = function() return 90 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_recap", true)
		check("the level cap is one question", addon.island_vitals.at_cap(90) == true and addon.island_vitals.at_cap(12) == false)
		check("the level cap baseline stays quiet", #addon.island.view().notices == 0)
		check("an empty bar at the level cap counts no experience", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("XP gained: 0", 1, true)
			and not notice_key(addon, "session-recap").detail:find("XP incomplete", 1, true))
		local addon2, env2, event2, state2 = island_world()
		state2.level, state2.xp, state2.xp_max = 89, 500, 1000
		env2.GetMaxPlayerLevel = function() return 90 end
		addon2.module.set("island", "enabled", true)
		addon2.module.set("island", "feed_recap", true)
		state2.level, state2.xp, state2.xp_max = 90, 0, 0
		event2("PLAYER_LEVEL_UP", 90)
		check("reaching the level cap keeps the last bar", show_recap(addon2, env2) == true
			and notice_key(addon2, "session-recap").detail:find("XP gained: 500", 1, true))
		local addon3, env3, _, state3 = island_world()
		state3.level, state3.xp, state3.xp_max = 12, 0, 0
		env3.GetMaxPlayerLevel = function() return 90 end
		addon3.module.set("island", "enabled", true)
		addon3.module.set("island", "feed_recap", true)
		check("a zero bar below the level cap stays incomplete", show_recap(addon3, env3) == true
			and notice_key(addon3, "session-recap").detail:find("XP incomplete", 1, true))
	end
end

-- Island history: the inbox kept across a reload or relog.
return function(_, check, lib)
	local island_world = lib.island_world
	do
		local function with_character(env)
			env.UnitGUID = function() return "Player-1-00000001" end
			env.GetServerTime = function() return 1000000 end
		end
		local first, first_env, first_event, first_state = island_world()
		with_character(first_env)
		first.module.set("island", "enabled", true)
		first.island.notify({ source = "Test", key = "kept", text = "Kept row", detail = "Some detail", money = 500 })
		first.island.notify({ source = "Test", key = "live", text = "Bags are full", severity = "warning", persist = true })
		first.island.notify({ source = "Test", key = "act", text = "Has action", actions = {
			{ id = "go", label = "Go", type = "callback", on_click = function() end } } })
		first_state.time = first_state.time + 120
		first_env.GetServerTime = function() return 1000120 end
		local saved = first_env.EverlookSaved
		first_event("PLAYER_LOGOUT")
		check("history saves per character", saved.island_history["Player-1-00000001"] ~= nil)

		local second, second_env = island_world()
		with_character(second_env)
		second_env.GetServerTime = function() return 1000300 end
		second_env.EverlookSaved = second_env.EverlookSaved or {}
		second_env.EverlookSaved.island_history = saved.island_history
		second.module.set("island", "enabled", true)
		local notices = second.island.view().notices
		local texts = {}
		for _, notice in ipairs(notices) do texts[#texts + 1] = notice.text end
		check("a reload brings back the plain history rows", table.concat(texts, ",") == "Kept row,Has action")
		check("a restored row keeps its detail, money and unread state",
			notices[1].detail == "Some detail" and notices[1].money == 500 and notices[1].unread == true)
		check("a restored row has no actions and no toast", #notices[2].actions == 0 and #second.island.view().toasts == 0)
	end
end

-- Island reputation: tells you when a faction reaches a higher standing.
return function(check, lib)
	local island_world = lib.island_world
	do
		local addon, env, event, state, _, tickers = island_world()
		local scans = 0
		env.C_Reputation = {
			GetNumFactions = function() scans = scans + 1; return 0 end,
			GetFactionDataByIndex = function() end,
		}
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_reputation", true)
		local baseline = scans
		for _ = 1, 5 do event("QUEST_LOG_UPDATE") end
		check("quest log bursts do not poll the reputation feed", scans == baseline)
		for _ = 1, 4 do state.time = state.time + 1; tickers[1].callback() end
		check("the timed poll keeps reputation on a slow beat", scans - baseline <= 1)
		state.time = state.time + 5
		tickers[1].callback()
		check("the slow beat still comes around", scans - baseline >= 1)
	end
end

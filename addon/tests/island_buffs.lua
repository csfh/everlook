-- Island buffs: warns when a long buff has under a minute left.
return function(check, lib)
	local island_world, notice_key = lib.island_world, lib.notice_key
	do
		local addon, env, _, state, _, tickers = island_world()
		env.InCombatLockdown = function() return false end
		local auras = {
			{ spellId = 1, name = "Flask", duration = 3600, expirationTime = 100 + 40 },
			{ spellId = 2, name = "Short buff", duration = 30, expirationTime = 100 + 20 },
			{ spellId = 3, name = "Well Fed", duration = 900, expirationTime = 100 + 200 },
		}
		env.C_UnitAuras = { GetAuraDataByIndex = function(_, index) return auras[index] end }
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_buffs", true)
		check("a buff already inside the window stays quiet", #addon.island.view().notices == 0)
		state.time = state.time + 150
		tickers[1].callback()
		local notice = notice_key(addon, "buff:3:300")
		check("a long buff warns once it is under a minute from the end",
			notice and notice.text == "Well Fed is about to run out" and notice.severity == "warning" and notice.spell_id == 3)
		check("a short buff never warns", notice_key(addon, "buff:2:120") == nil)
		local count = #addon.island.view().notices
		state.time = state.time + 6
		tickers[1].callback()
		check("the same buff does not warn twice", #addon.island.view().notices == count)
		auras[3] = nil
		state.time = state.time + 6
		tickers[1].callback()
		check("the warning goes away when the buff does", notice_key(addon, "buff:3:300") == nil)
		env.InCombatLockdown = function() return true end
		auras[1] = { spellId = 4, name = "Elixir", duration = 600, expirationTime = state.time + 10 }
		state.time = state.time + 6
		tickers[1].callback()
		check("combat skips the buff scan", notice_key(addon, "buff:4:" .. math.floor(state.time + 4)) == nil)
	end
end

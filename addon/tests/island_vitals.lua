-- Island vitals: the level, experience, money, durability and bag readings the island and its feeds share.
return function(check, lib)
	local read_source, island_world = lib.read_source, lib.island_world
	do
		local addon, _, event, state = island_world()
		addon.module.set("island", "enabled", true)
		event("PLAYER_LEVEL_UP", 13)
		event("PLAYER_LEVEL_UP", 13)
		check("a readable level event outruns a delayed getter exactly once", addon.island.view().level == 13 and #addon.island.view().notices == 1)
		state.level = 13
		event("PLAYER_XP_UPDATE", "player")
		check("the level getter catches up without another notice", addon.island.view().level == 13 and #addon.island.view().notices == 1)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.GetMoney = nil
		env.GetInventoryItemDurability = nil
		env.C_Container = nil
		env.GetGameTime = nil
		addon.module.set("island", "enabled", true)
		local view = addon.island.view()
		check("a missing readout API leaves that field blank and keeps experience",
			view.level == 12 and view.xp == 450 and view.money == nil and view.durability == nil and view.bags == nil and view.clock == nil)
		env.issecretvalue = function(value) return value == 450 or value == 1000 end
		state.xp, state.xp_max = 450, 1000
		event("PLAYER_XP_UPDATE", "player")
		check("secret experience still updates the bar values", addon.island.view().xp == 450 and addon.island.view().xp_max == 1000)
		env.issecretvalue = function(value) return value == 20 or value == 50 end
		state.slots[1], state.slots[5] = { 20, 50 }, nil
		event("UPDATE_INVENTORY_DURABILITY")
		check("secret durability is not turned into a percent", addon.island.view().durability == nil or addon.island.view().durability == "")
	end
	do
		local addon = island_world()
		local advance = addon.island_vitals.advance
		check("a bar advance is the shared experience delta",
			advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 10, xp = 250, xp_max = 1000 }) == 150
			and advance({ level = 10, xp = 400, xp_max = 1000 }, { level = 11, xp = 50, xp_max = 2000 }) == 650
			and advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 10, xp = 50, xp_max = 1000 }) == nil
			and advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 12, xp = 0, xp_max = 1000 }) == nil)
		local whole = addon.island_vitals.whole
		check("a bar reading is whole by the one shared rule", type(whole) == "function"
			and whole(12) == 12 and whole(0) == 0 and whole(-1) == nil and whole(1.5) == nil
			and whole(0 / 0) == nil and whole(math.huge) == nil and whole("12") == nil)
		check("experience detail keeps no rule of its own for a whole reading",
			not read_source("island_experience.lua"):find("local function whole", 1, true))
		check("island feeds read an item link's id through the core, with no parser of their own",
			not read_source("island_share.lua"):find("item:(%d+)", 1, true)
			and not read_source("island_loot.lua"):find("item:(%d+)", 1, true))
	end
end

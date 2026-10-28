-- Auto loot: loots each unlocked slot right away when the loot window opens with auto loot.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local looted = {}
	env.GetNumLootItems = function() return 3 end
	env.GetLootSlotInfo = function(slot) return nil, nil, nil, nil, nil, slot == 2 end
	env.LootSlot = function(slot) looted[#looted + 1] = slot end
	addon.module.set("auto_loot", "enabled", true)
	event("LOOT_OPENED", false)
	check("fast looting respects manual loot", #looted == 0)
	event("LOOT_OPENED", true)
	check("fast looting skips locked slots", #looted == 2 and looted[1] == 3 and looted[2] == 1)
end

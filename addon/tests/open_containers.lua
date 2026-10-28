-- Open containers: opens clam shells, crates, and other containers in your bags, then takes what is inside when that loot came from the container.
return function(check, lib)
	local load_all = lib.load_all
	do
		local function container_world()
			local module, world, event, _, timers = load_all()
			local bags = {
				{ itemID = 11, stackCount = 2, hasLoot = true },
				{ itemID = 12, stackCount = 1 },
				{ itemID = 13, stackCount = 1, hasLoot = true, isLocked = true },
				{ itemID = 14, stackCount = 1, hasLoot = true },
			}
			local state = { bags = bags, opened = {}, looted = {}, slots = 0, source = "Item-1-0-1", shown = false }
			world.NUM_BAG_SLOTS = 0
			world.C_Container = {
				GetContainerNumSlots = function() return 4 end,
				GetContainerItemInfo = function(_, slot) return bags[slot] end,
				UseContainerItem = function(_, slot) state.opened[#state.opened + 1] = slot end,
			}
			world.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
			world.C_Item = {
				DoesItemExist = function(location) return bags[location.slot] ~= nil end,
				GetItemGUID = function(location)
					assert(bags[location.slot], "an empty slot has no item GUID")
					return "Item-1-0-" .. location.slot
				end,
			}
			world.CursorHasItem = function() return false end
			world.GetCursorInfo = function() end
			world.SpellCanTargetItem = function() return false end
			world.SpellCanTargetItemID = function() return false end
			world.LootFrame = { IsShown = function() return state.shown end }
			world.GetNumLootItems = function() return state.slots end
			world.GetLootSourceInfo = function() return state.source, 1 end
			world.GetLootSlotInfo = function(slot)
				if slot < 1 or slot > state.slots then return end
				return "tex", "Clam", 1, nil, 1, slot == 2
			end
			world.LootSlot = function(slot) state.looted[#state.looted + 1] = slot end
			return module, world, event, timers, state
		end
		local opener, open_env, open_event, open_tickers, container = container_world()
		open_event("BAG_UPDATE_DELAYED")
		check("containers stay closed while the module is off", #container.opened == 0)
		opener.module.set("open_containers", "enabled", true)
		check("a lootable container is opened and a plain item stays closed", container.opened[1] == 1 and #container.opened == 1)
		container.slots = 2
		open_event("LOOT_OPENED", false, true)
		check("the container's loot is taken and a locked slot stays", container.looted[1] == 1 and #container.looted == 1)
		open_event("LOOT_OPENED", false, true)
		check("a loot window the module did not open stays as it is", #container.looted == 1)
		container.slots = 0
		open_env.MerchantFrame = { IsShown = function() return true end }
		open_event("LOOT_CLOSED")
		open_event("BAG_UPDATE_DELAYED")
		check("a merchant does not get the container sold", #container.opened == 1)
		open_env.MerchantFrame.IsShown = function() return false end
		open_env.IsShiftKeyDown = function() return true end
		open_event("MERCHANT_CLOSED")
		check("Shift pauses opening containers", #container.opened == 1)
		open_env.IsShiftKeyDown = function() return false end
		open_env.InCombatLockdown = function() return true end
		open_event("BAG_UPDATE_DELAYED")
		check("combat waits to open a container", #container.opened == 1)
		open_env.InCombatLockdown = function() return false end
		open_event("PLAYER_REGEN_ENABLED")
		check("leaving combat skips the unchanged opened container", container.opened[2] == 4)
		for _ = 1, 3 do open_tickers[#open_tickers].callback() end
		check("a container that does not open is left alone", #container.opened == 2)
		opener.module.set("open_containers", "enabled", false)
		open_event("BAG_UPDATE_DELAYED")
		check("turning container opening off stops it", #container.opened == 2 and open_tickers[#open_tickers].cancelled)

		local foreign, foreign_env, foreign_event, foreign_timers, foreign_state = container_world()
		foreign.module.set("open_containers", "enabled", true)
		foreign_state.slots = 1
		foreign_state.source = "Creature-0-0-0-0-11-1"
		foreign_event("LOOT_OPENED", false, false)
		foreign_timers[1].callback()
		check("a corpse window arriving during an open stays manual", #foreign_state.looted == 0)
		foreign_state.slots = 0
		foreign_event("LOOT_CLOSED")
		foreign_state.slots = 1
		foreign_state.source = "Item-1-0-99"
		foreign_event("LOOT_OPENED", false, true)
		check("a different item's loot is not attributed to the pending container", #foreign_state.looted == 0)

		for _, guard in ipairs({ "IsShiftKeyDown", "InCombatLockdown", "CursorHasItem", "SpellCanTargetItem", "SpellCanTargetItemID" }) do
			local paused, paused_env, paused_event, paused_timers, paused_state = container_world()
			paused.module.set("open_containers", "enabled", true)
			paused_env[guard] = function() return true end
			paused_state.slots = 1
			paused_event("LOOT_OPENED", false, true)
			paused_env[guard] = function() return false end
			paused_timers[1].callback()
			check(guard .. " after opening leaves the loot manual", #paused_state.looted == 0)
		end
		local merchant, merchant_env, merchant_event, _, merchant_state = container_world()
		merchant.module.set("open_containers", "enabled", true)
		merchant_env.MerchantFrame = { IsShown = function() return true end }
		merchant_state.slots = 1
		merchant_event("LOOT_OPENED", false, true)
		check("a merchant opening before the loot arrives pauses taking it", #merchant_state.looted == 0)

		for _, api in ipairs({ "IsShiftKeyDown", "InCombatLockdown", "CursorHasItem", "GetCursorInfo", "SpellCanTargetItem", "SpellCanTargetItemID", "GetNumLootItems", "GetLootSlotInfo", "GetLootSourceInfo", "LootSlot", "ItemLocation", "C_Item", "LootFrame" }) do
			local missing, missing_env, _, _, missing_state = container_world()
			missing_env[api] = false
			missing.module.set("open_containers", "enabled", true)
			check("container opening fails closed without " .. api, #missing_state.opened == 0)
		end
		local unknown, unknown_env, unknown_event, _, unknown_state = container_world()
		unknown.module.set("open_containers", "enabled", true)
		unknown_env.GetLootSourceInfo = function() end
		unknown_state.slots = 1
		unknown_event("LOOT_OPENED", false, true)
		check("loot with no source GUID stays manual", #unknown_state.looted == 0)
		local secret, secret_env, secret_event, _, secret_state = container_world()
		secret.module.set("open_containers", "enabled", true)
		secret_env.issecretvalue = function(value) return value == secret_state.source end
		secret_state.slots = 1
		secret_event("LOOT_OPENED", false, true)
		check("a secret loot source stays manual", #secret_state.looted == 0)
		local unannounced, _, _, unannounced_timers, unannounced_state = container_world()
		unannounced.module.set("open_containers", "enabled", true)
		unannounced_state.slots = 1
		unannounced_timers[1].callback()
		check("the polling timer does not claim an unannounced loot window", #unannounced_state.looted == 0)
		local identical, _, _, identical_timers, identical_state = container_world()
		identical_state.bags[4].itemID = 11
		identical_state.bags[4].stackCount = 2
		identical.module.set("open_containers", "enabled", true)
		for _ = 1, 3 do identical_timers[1].callback() end
		check("an unopened box does not suppress a different stack of the same item", identical_state.opened[2] == 4)
		local removed, _, _, removed_timers, removed_state = container_world()
		removed.module.set("open_containers", "enabled", true)
		removed_state.bags[1] = nil
		removed_timers[1].callback()
		check("an item removed while opening is not queried for a GUID", removed_state.opened[2] == 4)
		local empty, empty_env, _, _, empty_state = container_world()
		empty_state.shown = true
		empty.module.set("open_containers", "enabled", true)
		check("an existing empty loot window prevents opening a container", #empty_state.opened == 0)
		empty_state.shown = false
		empty_env.GetNumLootItems = function() end
		empty.module.set("open_containers", "enabled", true)
		check("an unknown loot count prevents opening a container", #empty_state.opened == 0)
		local money, money_env, _, _, money_state = container_world()
		money_env.GetCursorInfo = function() return "money", 10 end
		money.module.set("open_containers", "enabled", true)
		check("holding money on the cursor pauses container opening", #money_state.opened == 0)
		local mixed, mixed_env, mixed_event, _, mixed_state = container_world()
		mixed.module.set("open_containers", "enabled", true)
		mixed_env.GetLootSourceInfo = function() return mixed_state.source, 1, "Item-1-0-99", 1 end
		mixed_state.slots = 1
		mixed_event("LOOT_OPENED", false, true)
		check("a slot with mixed loot sources stays manual", #mixed_state.looted == 0)
		local closing, closing_env, closing_event, closing_timers, closing_state = container_world()
		closing.module.set("open_containers", "enabled", true)
		closing_env.LootSlot = function(slot)
			closing_state.looted[#closing_state.looted + 1] = slot
			closing_state.slots = 0
			closing_event("LOOT_CLOSED")
		end
		closing_state.slots = 1
		closing_event("LOOT_OPENED", false, true)
		check("loot closing inside LootSlot does not reenter container use", #closing_state.opened == 1 and #closing_state.looted == 1)
		closing_timers[1].callback()
		check("the next container opens after the previous loot call returns", closing_state.opened[2] == 4)
		local interrupted, interrupted_env, interrupted_event, _, interrupted_state = container_world()
		interrupted.module.set("open_containers", "enabled", true)
		interrupted_env.LootSlot = function(slot)
			interrupted_state.looted[#interrupted_state.looted + 1] = slot
			interrupted_env.IsShiftKeyDown = function() return true end
		end
		interrupted_state.slots = 3
		interrupted_event("LOOT_OPENED", false, true)
		check("Shift interrupts taking the remaining loot slots", #interrupted_state.looted == 1 and interrupted_state.looted[1] == 3)
	end
end

-- Sell junk: sells gray items when a vendor opens, and says what that junk brought in once selling stops.
return function(check, lib)
	local read_source, load_all, island_world, fire_after = lib.read_source, lib.load_all, lib.island_world, lib.fire_after
	local addon2, env2, event2, hooks, tickers, frames = load_all()
	local bags = {
		{ itemID = 1, quality = 0, stackCount = 2 },
		{ itemID = 2, quality = 0, stackCount = 1 },
		{ itemID = 3, quality = 1, stackCount = 1 },
		{ itemID = 4, quality = 0, stackCount = 1, isLocked = true },
	}
	local sold, report = {}, nil
	env2.NUM_BAG_SLOTS = 0
	env2.C_Item = {
		GetItemInfo = function()
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
	}
	env2.C_Container = {
		GetContainerNumSlots = function() return 4 end,
		GetContainerItemInfo = function(_, slot) return bags[slot] end,
		UseContainerItem = function(_, slot) sold[#sold + 1] = slot; bags[slot] = nil end,
	}
	addon2.say = function(text) report = text end
	addon2.module.set("sell_junk", "enabled", true)
	event2("MERCHANT_SHOW")
	tickers[1].callback(); tickers[1].callback(); tickers[1].callback()
	check("junk sale skips locked and non-junk items", #sold == 2 and sold[1] == 1 and sold[2] == 2)
	check("junk sale reports confirmed stack proceeds", report and report:find("30 copper", 1, true) and tickers[1].cancelled)
	check("junk selling has no command and no protection list",
		env2.SLASH_EVERLOOKJUNK1 == nil and addon2.sell_junk == nil and env2.EverlookSaved.modules.sell_junk.protected == nil)
	bags[1] = { itemID = 5, quality = 0, stackCount = 1 }
	event2("MERCHANT_SHOW")
	event2("MERCHANT_CLOSED")
	tickers[2].callback()
	check("closing vendor cancels queued sales", #sold == 2 and tickers[2].cancelled)

	local addon3, env3, event3, _, tickers3 = load_all()
	local bags3 = {
		{ itemID = 1, quality = 0, stackCount = 1 },
		{ itemID = 2, quality = 0, stackCount = 1, questID = 42, isActive = false },
		{ itemID = 3, quality = 0, stackCount = 1 },
		{ itemID = 4, quality = 0, stackCount = 1 },
		{ itemID = 5, quality = 0, stackCount = 1 },
		{ itemID = 6, quality = 0, stackCount = 1 },
		{ itemID = 7, quality = 0, stackCount = 1 },
		{ itemID = 8, quality = 0, stackCount = 1 },
		{ itemID = 9, quality = 0, stackCount = 1, questID = 15, isActive = false },
		{ itemID = 10, quality = 0, stackCount = 1 },
	}
	local sold3 = {}
	env3.NUM_BAG_SLOTS = 0
	env3.C_Item = {
		GetItemInfo = function(item_id)
			if item_id == 7 then return nil end
			if item_id == 3 then
				return "Thread", nil, 0, 1, 0, "Tradeskill", "Parts", 20, "", 1, 10, 7, 0, 0, 0, nil, true
			end
			if item_id == 5 then
				return "Ore", nil, 0, 1, 0, "Tradeskill", "Parts", 20, "", 1, 10, 7, 0, 0, 0, nil, true
			end
			if item_id == 8 then
				return "Recipe", nil, 0, 1, 0, "Recipe", "Book", 1, "", 1, 10, 9, 0, 0, 0, nil, false
			end
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
		GetItemSpell = function(item_id)
			if item_id == 4 then return "Teach", 99 end
		end,
	}
	env3.C_Container = {
		GetContainerNumSlots = function() return #bags3 end,
		GetContainerItemInfo = function(_, slot) return bags3[slot] end,
		UseContainerItem = function(_, slot)
			sold3[#sold3 + 1] = slot
			bags3[slot] = nil
		end,
	}
	addon3.module.set("sell_junk", "enabled", true)
	event3("MERCHANT_SHOW")
	tickers3[1].callback()
	tickers3[1].callback()
	tickers3[1].callback()
	tickers3[1].callback()
	check("junk sale keeps quest items, recipes, and reagents", sold3[1] == 1 and sold3[2] == 6 and sold3[3] == 10 and #sold3 == 3)
	do
		-- Sell junk with items the player marked in Bags, using the real Bags module.
		-- Marked items go through the same checks as a grey item, except the grey quality.
		-- One vendor visit. `setup` can change the world after the Bags settings are in place and
		-- before the vendor opens. `during` runs after the vendor opened and before the first sale.
		local function visit(setup, during)
			local addon, env, event, _, tickers = load_all()
			local slots = {
				{ itemID = 1, quality = 0, stackCount = 1 },
				{ itemID = 2, quality = 1, stackCount = 1 },
				{ itemID = 3, quality = 1, stackCount = 1 },
			}
			local sold = {}
			env.NUM_BAG_SLOTS = 0
			local prices = { [1] = 10, [2] = 10, [3] = 10 }
			env.C_Item = {
				GetItemInfo = function(item_id)
					return "Item", nil, 1, 1, 0, "Miscellaneous", "Junk", 20, "", 1, prices[item_id], 15, 0, 0, 0, nil, false
				end,
			}
			env.C_Container = {
				GetContainerNumSlots = function() return #slots end,
				GetContainerItemInfo = function(_, slot) return slots[slot] end,
				UseContainerItem = function(_, slot) sold[#sold + 1] = slot; slots[slot] = nil end,
			}
			addon.say = function() end
			addon.module.set("sell_junk", "enabled", true)
			addon.module.set("sell_junk", "marked_junk", true)
			addon.module.set("bags", "enabled", true)
			addon.module.set("bags", "junk_marker", true)
			-- The player marked item 3 in Bags.
			addon.bags_junk.toggle(addon.bags_junk.data(), 3)
			local world = { slots = slots, prices = prices, addon = addon, env = env, reagents = {}, spells = {} }
			env.C_Item.GetItemInfo = function(item_id)
				local reagent = world.reagents[item_id] or false
				return "Item", nil, 1, 1, 0, "Miscellaneous", "Junk", 20, "", 1, prices[item_id], 15, 0, 0, 0, nil, reagent
			end
			env.C_Item.GetItemSpell = function(item_id)
				local spell = world.spells[item_id]
				if spell then return "Teach", spell end
			end
			if setup then setup(world) end
			event("MERCHANT_SHOW")
			if during then during(world) end
			for _ = 1, 8 do
				for _, ticker in ipairs(tickers) do
					if not ticker.cancelled then ticker.callback() end
				end
			end
			table.sort(sold)
			return table.concat(sold, ","), world
		end

		check("a grey item and a marked item sell, and an unmarked white item stays", (visit()) == "1,3")
		check("without the option only the grey item sells", (visit(function(w) w.addon.module.set("sell_junk", "marked_junk", false) end)) == "1")
		check("the option is off until it is turned on", (function()
			local addon = load_all()
			for _, module in ipairs(addon.module.modules) do
				if module.id == "sell_junk" then return module.options.marked_junk and module.options.marked_junk.default == false end
			end
		end)())
		check("with Bags off a marked item stays", (visit(function(w) w.addon.module.set("bags", "enabled", false) end)) == "1")
		check("with the marker off a marked item stays", (visit(function(w) w.addon.module.set("bags", "junk_marker", false) end)) == "1")
		check("with no Bags table a marked item stays and grey still sells", (visit(function(w) w.addon.bags = nil end)) == "1")
		check("with no is_junk function a marked item stays", (visit(function(w) w.addon.bags = {} end)) == "1")
		check("an answer that is not exactly true sells nothing extra", (visit(function(w) w.addon.bags = { is_junk = function() return "yes" end } end)) == "1")
		check("an answer of true for an item sells it", (visit(function(w) w.addon.bags = { is_junk = function(item_id) return item_id == 2 end } end)) == "1,2")
		check("holding Shift when the vendor opens sells nothing", (visit(function(w) w.env.IsShiftKeyDown = function() return true end end)) == "")
		check("an item unmarked after the vendor opened is not sold", (visit(nil, function(w) w.addon.bags_junk.toggle(w.addon.bags_junk.data(), 3) end)) == "1")
		check("turning Bags off during the visit stops a marked sale but not a grey one", (visit(nil, function(w) w.addon.module.set("bags", "enabled", false) end)) == "1")
		check("turning the option off during the visit stops a marked sale", (visit(nil, function(w) w.addon.module.set("sell_junk", "marked_junk", false) end)) == "1")
		check("a marked item with no sell price stays", (visit(function(w) w.prices[3] = nil end)) == "1")
		check("a marked locked item stays", (visit(function(w) w.slots[3].isLocked = true end)) == "1")
		check("a marked item the game says has no value stays", (visit(function(w) w.slots[3].hasNoValue = true end)) == "1")
		check("a marked quest starter stays in the bag", (visit(function(w) w.slots[3].questID = 99; w.slots[3].isActive = false end)) == "1")
		check("a marked recipe stays in the bag", (visit(function(w) w.spells[3] = 5 end)) == "1")
		check("a marked crafting reagent stays in the bag", (visit(function(w) w.reagents[3] = true end)) == "1")
		check("a marked item with several copies in a stack sells the stack", (function()
			local result = visit(function(w) w.slots[3].stackCount = 5 end)
			return result == "1,3"
		end)())
	end
	check("junk uses one notice call", not read_source("sell_junk.lua"):find("confirm_money", 1, true))
	do
		local addon, env, event, state, afters, tickers = island_world()
		local items = { { itemID = 1, quality = 0, stackCount = 2 }, { itemID = 2, quality = 0, stackCount = 1 } }
		local reported, used = nil, 0
		env.NUM_BAG_SLOTS = 0
		env.C_Item = { GetItemInfo = function() return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 100, 15, 0, 0, 0, nil, false end }
		env.C_Container.GetContainerNumSlots = function() return 2 end
		env.C_Container.GetContainerItemInfo = function(_, slot) return items[slot] end
		env.C_Container.UseContainerItem = function(_, slot)
			used = used + 1
			state.money = state.money + items[slot].stackCount * 100
			items[slot] = nil
		end
		addon.say = function(text) reported = text end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("sell_junk", "enabled", true)
		event("MERCHANT_SHOW")
		local selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		check("an attempted junk sale has no island result", #addon.island.view().notices == 0)
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		local entry = addon.island.view().notices[1]
		check("confirmed junk proceeds reach the island before totals reset", entry and entry.text == "Junk sold" and entry.money == 300 and entry.severity == "success" and used == 2)
		check("the original junk chat report remains", reported and reported:find("300 copper", 1, true))
		fire_after(afters, 0.75)
		fire_after(afters, 0.75)
		check("a confirmed matching junk batch has one result", #addon.island.view().notices == 1)
		items[1] = { itemID = 1, quality = 0, stackCount = 2 }
		addon.module.set("island", "source_sell", false)
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		selling.callback()
		check("disabling the sale feed preserves selling and its chat report", used == 3 and #addon.island.view().notices == 1 and reported:find("200 copper", 1, true))
		event("PLAYER_MONEY")
		fire_after(afters, 0.75)
		addon.module.set("island", "source_sell", true)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.sell_junk" then error("display failed") end
			return original(payload)
		end
		items[1] = { itemID = 1, quality = 0, stackCount = 1 }
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		fire_after(afters, 0.75)
		local money_notice = addon.island.view().notices[2]
		check("sale display errors preserve chat and the routine-money fallback", #errors == 1 and reported:find("100 copper", 1, true) and money_notice and money_notice.text == "Money received" and money_notice.money == 300 and money_notice.count == 2)
	end
end

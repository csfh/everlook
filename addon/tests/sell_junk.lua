-- Sell junk: sells gray items when a vendor opens, and says what that junk brought in once selling stops.
return function(root, check, lib)
	local load_all = lib.load_all
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
end

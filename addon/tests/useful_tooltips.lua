-- Useful tooltips: adds item and creature IDs, a vendor price, and a bag count to the matching tooltip.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon2, env2, event2, hooks, tickers, frames = load_all()
	-- The vendor price the game reports for the test item, as the Sell junk tests set it.
	env2.C_Item = {
		GetItemInfo = function()
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
	}
	local posts, lines = {}, {}
	env2.Enum = { TooltipDataType = { Item = 1, Unit = 2, Spell = 3 } }
	env2.TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[kind] = callback end }
	env2.GetCoinTextureString = tostring
	env2.C_Item.GetItemCount = function() return 3 end
	local clear
	local tip = { AddLine = function(_, line) lines[#lines + 1] = line end,
		HasScript = function() return true end, HookScript = function(_, _, callback) clear = callback end }
	addon2.module.set("useful_tooltips", "enabled", true)
	posts[1](tip, { id = 1 }); posts[1](tip, { id = 1 })
	check("item tooltip adds IDs and vendor totals without duplicates", #lines == 3 and lines[3]:find("30", 1, true))
	clear(tip); posts[1](tip, { id = 1 })
	check("tooltip clear permits rendering same item again", #lines == 6)
	addon2.module.set("useful_tooltips", "enabled", false)
	clear(tip); posts[1](tip, { id = 1 })
	check("disabled tooltip hooks add no lines", #lines == 6)
end

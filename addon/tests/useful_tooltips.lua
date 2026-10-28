-- Useful tooltips: adds item and creature IDs, a vendor price, and a bag count to the matching tooltip.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env = load_all()
	-- The vendor price the game reports for the test item, as the Sell junk tests set it.
	env.C_Item = {
		GetItemInfo = function()
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
	}
	local posts, lines = {}, {}
	env.Enum = { TooltipDataType = { Item = 1, Unit = 2, Spell = 3 } }
	env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[kind] = callback end }
	env.GetCoinTextureString = tostring
	env.C_Item.GetItemCount = function() return 3 end
	local clear
	local tip = { AddLine = function(_, line) lines[#lines + 1] = line end,
		HasScript = function() return true end, HookScript = function(_, _, callback) clear = callback end }
	addon.module.set("useful_tooltips", "enabled", true)
	posts[1](tip, { id = 1 }); posts[1](tip, { id = 1 })
	check("item tooltip adds IDs and vendor totals without duplicates", #lines == 3 and lines[3]:find("30", 1, true))
	clear(tip); posts[1](tip, { id = 1 })
	check("tooltip clear permits rendering same item again", #lines == 6)
	addon.module.set("useful_tooltips", "enabled", false)
	clear(tip); posts[1](tip, { id = 1 })
	check("disabled tooltip hooks add no lines", #lines == 6)

	do
		-- On the game's tooltip processor, with the lighter stand-ins of load_files.
		local addon, play, fire = lib.load_files({ "world", "module", "tooltips", "useful_tooltips" })
		play.TooltipDataProcessor = {
			AddTooltipPostCall = function(kind, callback)
				play.tooltip_calls = play.tooltip_calls or {}
				play.tooltip_calls[kind] = callback
			end,
		}
		play.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
		play.Enum = { TooltipDataType = { Item = 0, Unit = 2 }, GossipOption = { Vendor = 1, Gossip = 2, Taxi = 3, Trainer = 4, Binder = 5 } }
		-- Tooltips install on enable, after the processor exists. Reload the module's apply by setting enabled.
		addon.module.set("useful_tooltips", "enabled", true)
		local lines = {}
		local tooltip = {
			AddLine = function(_, text)
				lines[#lines + 1] = text
			end,
			HasScript = function()
				return true
			end,
			HookScript = function() end,
		}
		play.tooltip_calls[0](tooltip, { id = 20 })
		local joined = table.concat(lines, "|")
		check("the item tooltip shows the item id", joined:find("Item ID: 20", 1, true) ~= nil)
		lines = {}
		play.issecretvalue = function(value)
			return value == "secret"
		end
		play.tooltip_calls[0](tooltip, { id = "secret" })
		check("a secret tooltip id adds no line", #lines == 0)
		play.issecretvalue = nil
	end
end

-- Island warnings: warns about low bag space and worn equipment, and sums up routine money changes.
return function(_, check, lib)
	local island_world, finish_animations, secret_stat = lib.island_world, lib.finish_animations, lib.secret_stat
	do
		local addon, env, event, state, afters = island_world()
		state.bags[0], state.bags[1], state.bags[5] = 8, 20, 100
		state.bag_families[1] = 32
		addon.module.set("island", "enabled", true)
		check("general free slots exclude specialty and reagent capacity", addon.island.view().bags == "8 free slots")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("ordinary bag changes stay quiet", #addon.island.view().notices == 0)
		state.bags[0] = 5
		event("BAG_UPDATE_DELAYED")
		local view = addon.island.view()
		local first = view.notices[1]
		check("low free slots produce one keyed warning", first and first.severity == "warning" and first.key == "free-slots")
		state.bags[0] = 0
		event("BAG_UPDATE_DELAYED")
		view = addon.island.view()
		check("full bags strengthen the same warning identity", #view.notices == 1 and view.notices[1].id == first.id and view.notices[1].severity == "error")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("bag warning retains its recovery margin", #addon.island.view().notices == 1)
		state.bags[0] = 8
		event("BAG_UPDATE_DELAYED")
		check("bag recovery resolves the condition without another notice", #addon.island.view().notices == 0)
		state.money = 22345
		event("PLAYER_MONEY")
		check("money updates quietly by default", #addon.island.view().notices == 0 and addon.island.view().money == "2g 23s 45c")
	end
	do
		local addon, _, event, state, afters = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		state.money = 12445
		event("PLAYER_MONEY")
		local stale = afters[#afters] and afters[#afters].callback
		state.time = 100.2
		state.money = 12645
		event("PLAYER_MONEY")
		check("routine money waits for a quiet window", #addon.island.view().notices == 0)
		if stale then stale() end
		check("an earlier batch deadline cannot publish a partial delta", #addon.island.view().notices == 0)
		local current = afters[#afters] and afters[#afters].callback
		if current then current() end
		local entry = addon.island.view().notices[1]
		check("routine money publishes one signed rich net amount", entry and entry.money == 300 and entry.text == "Money received")
		local before = #addon.island.view().notices
		state.money = 12646
		event("PLAYER_MONEY")
		if afters[#afters] then afters[#afters].callback() end
		check("tiny routine money deltas stay quiet", #addon.island.view().notices == before)
		state.money = 22646
		event("PLAYER_MONEY")
		local disabled = afters[#afters] and afters[#afters].callback
		addon.module.set("island", "source_money", false)
		if disabled then disabled() end
		check("turning off money delivery cancels pending batches", #addon.island.view().notices == before)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		state.slots[1] = { 14, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		local handle = addon.island.view().notices[1].id
		check("weakest-item damage crosses a threshold despite healthier gear", addon.island.view().durability == "28%")
		state.slots[1] = { 4, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("severe damage updates one condition", #addon.island.view().notices == 1 and addon.island.view().notices[1].id == handle)
		state.slots[1] = { 0, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a broken item strengthens the same condition", addon.island.view().notices[1].severity == "error")
		state.slots[1] = { 18, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("durability recovery resolves the retained warning", #addon.island.view().notices == 0)
		state.bags[0], state.bags[1] = 3, 1
		event("BAG_UPDATE_DELAYED")
		addon.module.set("island", "source_bags", false)
		check("disabling a condition source removes its warning immediately", #addon.island.view().notices == 0)
		finish_animations(frames)
		addon.module.set("island", "source_money", true)
		state.money = 12545
		event("BAG_UPDATE_DELAYED")
		event("PLAYER_MONEY")
		local maximum = afters[#afters - 1].callback
		state.time = 101
		state.money = 12745
		event("PLAYER_MONEY")
		maximum()
		check("other readouts preserve the money baseline and maximum-window total", addon.island.view().notices[1].money == 400)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		env.C_Container.GetContainerNumFreeSlots = function(bag) return 20, bag == 0 and 0 or secret end
		addon.module.set("island", "source_bags", true)
		event("BAG_UPDATE_DELAYED")
		check("secret bag classification leaves capacity unavailable without a warning", addon.island.view().bags == nil and #addon.island.view().notices == 1)
	end
end

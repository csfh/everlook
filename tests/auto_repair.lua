-- Auto repair: repairs your gear when a repair vendor opens and something needs repair.
return function(check, lib)
	local read_source, load_all, island_world, fire_after, secret_stat = lib.read_source, lib.load_all, lib.island_world, lib.fire_after, lib.secret_stat
	local addon, env, event = load_all()
	local repairs = {}
	env.CanMerchantRepair = function() return true end
	env.GetRepairAllCost = function() return 100, true end
	env.GetMoney = function() return 99 end
	env.RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
	addon.module.set("auto_repair", "enabled", true)
	event("MERCHANT_SHOW")
	check("repair requires sufficient funds", #repairs == 0)
	env.GetMoney = function() return 100 end
	event("MERCHANT_SHOW")
	check("personal repair uses available gold", #repairs == 1 and repairs[1] == false)
	env.CanGuildBankRepair = function() return true end
	env.GetGuildBankWithdrawMoney = function() return 50 end
	env.GetGuildBankMoney = function() return 1000 end
	addon.module.set("auto_repair", "guild_funds", true)
	event("MERCHANT_SHOW")
	check("insufficient guild allowance falls back to personal gold", repairs[2] == false)
	env.GetGuildBankWithdrawMoney = function() return -1 end
	event("MERCHANT_SHOW")
	check("unlimited guild allowance permits repair", repairs[3] == true)
	check("repair uses one notice call", not read_source("auto_repair.lua"):find("confirm_money", 1, true))
	do
		local addon, env, event, state, afters = island_world()
		local requests, cost, needed = {}, 500, true
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function(guild) requests[#requests + 1] = guild end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		check("requesting repair does not announce success", #requests == 1 and #addon.island.view().notices == 0)
		state.money = state.money - 500
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local entry = addon.island.view().notices[1]
		check("confirmed personal repair reports rich cost and fund source", entry and entry.text == "Equipment repaired" and entry.money == -500 and entry.detail == "Paid from personal funds")
		fire_after(afters, 0.75)
		check("a matching confirmed cost consumes only its pending money summary", #addon.island.view().notices == 1)
		state.money = state.money - 300
		event("PLAYER_MONEY")
		cost, needed = 300, true
		env.CanGuildBankRepair = function() return true end
		env.GetGuildBankWithdrawMoney = function() return -1 end
		env.GetGuildBankMoney = function() return 1000 end
		addon.module.set("auto_repair", "guild_funds", true)
		event("MERCHANT_SHOW")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local notices = addon.island.view().notices
		entry = notices[#notices]
		check("confirmed guild repair identifies guild payment", requests[2] == true and entry.detail == "Paid from guild funds" and entry.money == -800 and entry.count == 2)
		fire_after(afters, 0.75)
		entry = addon.island.view().notices
		check("a guild repair leaves an equal personal money batch", #entry == 2 and entry[1].detail == "Paid from guild funds" and entry[1].money == -800 and entry[2].text == "Money spent" and entry[2].money == -300)
		local count = #entry
		cost, needed = 100, true
		event("MERCHANT_SHOW")
		event("MERCHANT_CLOSED")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("closing the vendor cancels an unconfirmed repair notice", #addon.island.view().notices == count)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests = 100, true, 0
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("island", "money_min_silver", 0)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		state.money = state.money - 75 -- Includes a separate 25-copper gain.
		event("PLAYER_MONEY")
		event("UPDATE_INVENTORY_DURABILITY")
		check("an unchanged repair cost cannot confirm an attempted repair", #addon.island.view().notices == 0)
		cost, needed = 0, false
		fire_after(afters, 0.1)
		fire_after(afters, 0.75)
		local notices = addon.island.view().notices
		check("a delayed getter confirms after the observed durability event", #notices == 2 and notices[1].text == "Equipment repaired")
		check("mixed money batches preserve unrelated activity", notices[#notices].money == -75)
		cost, needed = 50, true
		event("MERCHANT_SHOW")
		fire_after(afters, 3)
		fire_after(afters, 3)
		fire_after(afters, 3)
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("expired repair observation does not announce late success", #addon.island.view().notices == 2)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		cost, needed = secret, true
		local ok = pcall(event, "MERCHANT_SHOW")
		check("secret repair cost prevents spending and formatting", ok and requests == 2)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests, errors = 100, true, 0, {}
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		local original = env.Everlook.island.notify
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.auto_repair" then error("display failed") end
			return original(payload)
		end
		event("MERCHANT_SHOW")
		state.money = state.money - 100
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		fire_after(afters, 0.75)
		local fallback = addon.island.view().notices[1]
		check("repair display failure leaves the completed action and money fallback", requests == 1 and #errors == 1 and fallback and fallback.money == -100)
	end
end

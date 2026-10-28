-- Auto repair: repairs your gear when a repair vendor opens and something needs repair.
return function(root, check, lib)
	local load_all = lib.load_all
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
end

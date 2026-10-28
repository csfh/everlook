-- Auto responses: when a summon confirmation, a resurrection offer, or a good item's delete confirmation appears, this accepts the summon or the resurrection and closes it, or types the delete word, if that choice below is on.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local confirmed, accepted_res, popups_hidden = 0, 0, {}
	env.Enum = { SummonReason = { Scenario = 2 } }
	env.C_SummonInfo = { ConfirmSummon = function() confirmed = confirmed + 1 end }
	env.AcceptResurrect = function() accepted_res = accepted_res + 1 end
	env.StaticPopup_Hide = function(which) popups_hidden[#popups_hidden + 1] = which end
	env.DELETE_ITEM_CONFIRM_STRING = "DELETE"
	event("CONFIRM_SUMMON", 0, false)
	event("RESURRECT_REQUEST", "Healer")
	check("auto responses do nothing while the module is off", confirmed == 0 and accepted_res == 0)

	addon.module.set("auto_responses", "enabled", true)
	event("CONFIRM_SUMMON", 0, false)
	check("a summon is accepted and its popup closes", confirmed == 1 and popups_hidden[#popups_hidden] == "CONFIRM_SUMMON")
	event("CONFIRM_SUMMON", 0, true)
	event("CONFIRM_SUMMON", 2, false)
	check("starting area and scenario summons stay manual", confirmed == 1)
	env.IsShiftKeyDown = function() return true end
	event("CONFIRM_SUMMON", 0, false)
	event("RESURRECT_REQUEST", "Healer")
	check("Shift pauses summons and resurrections", confirmed == 1 and accepted_res == 0)
	env.IsShiftKeyDown = function() return false end
	env.InCombatLockdown = function() return true end
	event("CONFIRM_SUMMON", 0, false)
	check("summons are not accepted in combat", confirmed == 1)
	event("RESURRECT_REQUEST", "Healer")
	check("a combat resurrection is accepted and its popups close",
		accepted_res == 1 and popups_hidden[#popups_hidden] == "RESURRECT_NO_TIMER"
		and popups_hidden[#popups_hidden - 1] == "RESURRECT_NO_SICKNESS" and popups_hidden[#popups_hidden - 2] == "RESURRECT")
	env.InCombatLockdown = nil
	event("CONFIRM_SUMMON", 0, false)
	check("a summon stays when the client cannot say whether you are in combat", confirmed == 1)
	env.InCombatLockdown = function() return false end
	addon.module.set("auto_responses", "accept_summons", false)
	addon.module.set("auto_responses", "accept_resurrections", false)
	event("CONFIRM_SUMMON", 0, false)
	event("RESURRECT_REQUEST", "Healer")
	check("each response has its own option", confirmed == 1 and accepted_res == 1)

	local typed
	local box = { SetText = function(_, text) typed = text end }
	local dialog = { GetEditBox = function() return box end }
	local shown = 0
	env.StaticPopupDialogs = { DELETE_GOOD_ITEM = { OnShow = function() shown = shown + 1 end } }
	env.hooksecurefunc = function(target, name, callback)
		local original = target[name]
		target[name] = function(...) original(...); callback(...) end
	end
	addon.module.set("auto_responses", "enabled", false)
	addon.module.set("auto_responses", "enabled", true)
	env.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("the delete popup keeps its own behavior and stays empty by default", shown == 1 and typed == nil)
	addon.module.set("auto_responses", "easy_delete", true)
	env.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("easy delete types the confirmation word", typed == "DELETE" and shown == 2)
	typed = nil
	env.IsShiftKeyDown = function() return true end
	env.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("Shift leaves the confirmation to be typed", typed == nil)
	env.IsShiftKeyDown = function() return false end
	addon.module.set("auto_responses", "enabled", false)
	env.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("turning the module off stops easy delete", typed == nil)
	addon.module.set("auto_responses", "enabled", true)
	local hooked_twice = shown
	env.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("the delete popup is hooked once, not once per enable", shown == hooked_twice + 1 and typed == "DELETE")
end

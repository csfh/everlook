-- Friend conveniences: when a party invite or a duel arrives, this accepts or declines it if the matching choice below is on, and closes that request.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local invited = 0
	env.GetNormalizedRealmName = function() return "Home" end
	env.C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Alice" } end }
	env.AcceptGroup = function() invited = invited + 1 end
	addon.module.set("friend_conveniences", "enabled", true)
	event("PARTY_INVITE_REQUEST", "Alice-Other")
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("invites from strangers and other realms stay manual", invited == 0)
	event("PARTY_INVITE_REQUEST", "Alice-Home")
	check("friend invites accepted", invited == 1)
	local declined, hidden_popups = 0, {}
	env.DeclineGroup = function() declined = declined + 1 end
	env.StaticPopup_Hide = function(which) hidden_popups[#hidden_popups + 1] = which end
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("other invites are left alone unless declining is on", declined == 0)
	addon.module.set("friend_conveniences", "decline_others", true)
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("other invites are declined and the popup closes", declined == 1 and hidden_popups[#hidden_popups] == "PARTY_INVITE")
	event("PARTY_INVITE_REQUEST", "Alice-Home")
	check("a friend is accepted, not declined", declined == 1 and invited == 2)
	env.IsShiftKeyDown = function() return true end
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("Shift pauses declining", declined == 1)
	env.IsShiftKeyDown = function() return false end
	do
		local accept, combat = env.AcceptGroup, env.InCombatLockdown
		env.AcceptGroup = nil
		event("PARTY_INVITE_REQUEST", "Alice-Home")
		check("a friend's invite is never declined when the client cannot accept it", declined == 1)
		env.AcceptGroup = accept
		env.InCombatLockdown = nil
		event("PARTY_INVITE_REQUEST", "Stranger")
		check("without a combat check nothing is accepted or declined", declined == 1)
		env.InCombatLockdown = combat
	end
	addon.module.set("friend_conveniences", "decline_others", false)

	;(function()
		local real_type = env.type or type
		local secret_name = {}
		env.type = function(value)
			if rawequal(value, secret_name) then return "string" end
			return real_type(value)
		end
		env.issecretvalue = function(value) return rawequal(value, secret_name) end
		local secret_invite = pcall(event, "PARTY_INVITE_REQUEST", secret_name)
		check("a secret invite name does not error or accept", secret_invite and invited == 2)
		env.C_FriendList = {
			GetNumFriends = function() return 2 end,
			GetFriendInfoByIndex = function(index)
				if index == 1 then return { name = secret_name } end
				return { name = "Alice" }
			end,
		}
		local secret_roster = pcall(event, "PARTY_INVITE_REQUEST", "Alice-Home")
		check("a secret friend name does not stop a later friend from matching", secret_roster and invited == 3)
		env.type = nil
		env.issecretvalue = nil
		env.C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Alice" } end }
	end)()
end

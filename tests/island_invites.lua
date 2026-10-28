-- Island invites: shows a toast when someone invites you to a group.
return function(check, lib)
	local island_world, notice_key = lib.island_world, lib.notice_key
	do
		local addon, _, event = island_world()
		addon.module.set("island", "enabled", true)
		event("PARTY_INVITE_REQUEST", "Thrall", false, false, false)
		check("an invite stays quiet while the feed is off", notice_key(addon, "party-invite") == nil)
		addon.module.set("island", "feed_invites", true)
		event("PARTY_INVITE_REQUEST", "Thrall", false, false, false)
		local notice = notice_key(addon, "party-invite")
		check("an invite shows the name and points to the popup", notice and notice.text == "Thrall invited you to a group"
			and notice.detail == "Answer in the invitation popup" and #notice.actions == 0)
		event("PARTY_INVITE_REQUEST", "Jaina", false, true, false)
		check("a finder invite names the role", notice_key(addon, "party-invite").detail == "Looking for a healer")
		event("PARTY_INVITE_CANCEL")
		check("a cancelled invite goes away", notice_key(addon, "party-invite") == nil)
		addon.island.apply_preset("Quiet")
		check("the Quiet preset turns invites off", addon.module.get("island", "feed_invites") == false)
	end
end

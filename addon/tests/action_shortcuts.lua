-- Action shortcuts: shortens Shift and Alt on the default action bars, so s-4 and a-4 read as S4 and A4, and s-a-4 reads as SA4.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	do
		local function action_button(text)
			local button = { binding_text = text, HotKey = { text = text } }
			function button.HotKey:GetText() return self.text end
			function button.HotKey:SetText(value) self.text = value end
			function button:UpdateHotkeys() self.HotKey:SetText(self.binding_text) end
			return button
		end
		local shift_button, alt_button = action_button("s-4"), action_button("a-4")
		local manager = { frames = { shift_button, alt_button } }
		function manager:ForEachFrame(callback)
			for _, button in ipairs(self.frames) do callback(button) end
		end
		function manager:RegisterFrame(button) self.frames[#self.frames + 1] = button end
		env.ActionBarButtonEventsFrame = manager
		check("action shortcuts keep Blizzard labels while disabled", shift_button.HotKey.text == "s-4" and alt_button.HotKey.text == "a-4")
		addon.module.set("action_shortcuts", "enabled", true)
		check("action shortcuts show Shift and Alt without a dash", shift_button.HotKey.text == "S4" and alt_button.HotKey.text == "A4")
		event("PLAYER_ENTERING_WORLD")
		shift_button.binding_text = "a-7"
		shift_button:UpdateHotkeys()
		check("native binding refreshes keep compact shortcuts", shift_button.HotKey.text == "A7")
		local combined_button = action_button("s-a-4")
		manager:RegisterFrame(combined_button)
		combined_button:UpdateHotkeys()
		check("new action buttons get combined modifier shortcuts", combined_button.HotKey.text == "SA4")
		for _, pair in ipairs({ { "4", "4" }, { "F4", "F4" }, { "s-F4", "SF4" }, { "a--", "A-" }, { "a-s-4", "AS4" }, { "c-4", "c-4" }, { "", "" }, { "•", "•" } }) do
			alt_button.binding_text = pair[1]
			alt_button:UpdateHotkeys()
			check("action shortcuts preserve the key in " .. pair[1], alt_button.HotKey.text == pair[2])
		end
		env.issecretvalue = function(value) return value == "s-9" end
		alt_button.binding_text = "s-9"
		alt_button:UpdateHotkeys()
		check("secret shortcut labels stay unchanged", alt_button.HotKey.text == "s-9")
		env.issecretvalue = nil
		combined_button.HotKey:SetText("Other addon")
		addon.module.set("action_shortcuts", "enabled", false)
		check("disabling restores the latest native label", shift_button.HotKey.text == "a-7")
		check("disabling preserves a later external label", combined_button.HotKey.text == "Other addon")
		shift_button.binding_text = "s-5"
		shift_button:UpdateHotkeys()
		check("disabled hooks leave native shortcut refreshes alone", shift_button.HotKey.text == "s-5")
		local late_addon, late_env, late_event = load_all()
		late_addon.module.set("action_shortcuts", "enabled", true)
		local late_button = action_button("a-4")
		late_env.ActionBarButtonEventsFrame = { ForEachFrame = function(_, callback) callback(late_button) end, RegisterFrame = function() end }
		late_event("ADDON_LOADED", "Blizzard_ActionBar")
		check("action bars loaded after Everlook get compact shortcuts", late_button.HotKey.text == "A4")
	end
end

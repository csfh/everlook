-- Chat layout: moves each chat window's edit box above its tab, or above the window when it has no tab, and hides the chat buttons, while those choices are on, and sets how long lines stay before they fade, including after the game rebuilds those windows.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon7, env7, event7 = load_all()
	local function chat_frame(time_visible)
		local box = { points = { { "TOPLEFT", "frame", "BOTTOMLEFT", -5, -2 }, { "RIGHT", "bar", "RIGHT", 8, 0 } } }
		function box:GetNumPoints() return #self.points end
		function box:GetPoint(index) return unpack(self.points[index]) end
		function box:ClearAllPoints() self.points = {} end
		function box:SetPoint(...) self.points[#self.points + 1] = { ... } end
		local frame = { editBox = box, ScrollBar = { name = "bar" }, time = time_visible }
		function frame:GetTimeVisible() return self.time end
		function frame:SetTimeVisible(seconds) self.time = seconds end
		return frame
	end
	local function chat_button(shown)
		local button = { shown = shown }
		function button:IsShown() return self.shown end
		function button:Hide() self.shown = false end
		function button:Show() self.shown = true; if self.on_show then self.on_show(self) end end
		function button:HookScript(_, callback) self.on_show = callback end
		return button
	end
	env7.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
	env7.ChatFrame1, env7.ChatFrame2 = chat_frame(120), chat_frame(60)
	env7.ChatFrame1Tab = { name = "tab" }
	env7.ChatFrameMenuButton, env7.ChatFrameChannelButton = chat_button(true), chat_button(true)
	env7.ChatFrameToggleVoiceMuteButton = chat_button(false)
	local function anchors(box)
		local list = {}
		for _, point in ipairs(box.points) do list[#list + 1] = table.concat({ point[1], type(point[2]) == "table" and point[2].name or point[2], point[3], point[4], point[5] }, ",") end
		return table.concat(list, ";")
	end
	check("chat layout changes nothing while off", anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0" and env7.ChatFrameMenuButton.shown)

	addon7.module.set("chat_layout", "enabled", true)
	check("the edit box moves above the chat tab", anchors(env7.ChatFrame1.editBox) == "BOTTOMLEFT,tab,TOPLEFT,-5,2;RIGHT,bar,RIGHT,8,0")
	check("a chat window with no tab uses the window itself",
		env7.ChatFrame2.editBox.points[1][2] == env7.ChatFrame2 and env7.ChatFrame2.editBox.points[1][3] == "TOPLEFT")
	check("the chat buttons are hidden", not env7.ChatFrameMenuButton.shown and not env7.ChatFrameChannelButton.shown)
	check("the fade time starts at the game default", env7.ChatFrame1.time == 120 and env7.ChatFrame2.time == 120)
	addon7.module.set("chat_layout", "fade_seconds", 30)
	check("the fade slider sets how long chat stays", env7.ChatFrame1.time == 30 and env7.ChatFrame2.time == 30)
	env7.ChatFrameMenuButton:Show()
	check("a button the game shows again is hidden again", not env7.ChatFrameMenuButton.shown)

	env7.ChatFrame1.editBox.points = { { "TOPLEFT", "frame", "BOTTOMLEFT", -5, -2 } }
	event7("UPDATE_CHAT_WINDOWS")
	check("a chat window refresh puts the edit box back on top", env7.ChatFrame1.editBox.points[1][1] == "BOTTOMLEFT")

	addon7.module.set("chat_layout", "editbox_top", false)
	check("clearing the edit box option restores its anchors", anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0")
	addon7.module.set("chat_layout", "hide_buttons", false)
	check("clearing the button option brings back the buttons that were shown", env7.ChatFrameMenuButton.shown and env7.ChatFrameChannelButton.shown and not env7.ChatFrameToggleVoiceMuteButton.shown)
	addon7.module.set("chat_layout", "editbox_top", true)
	addon7.module.set("chat_layout", "hide_buttons", true)
	addon7.module.set("chat_layout", "enabled", false)
	check("turning the module off restores anchors, fade time and buttons",
		anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0"
		and env7.ChatFrame1.time == 120 and env7.ChatFrame2.time == 60
		and env7.ChatFrameMenuButton.shown and env7.ChatFrameChannelButton.shown and not env7.ChatFrameToggleVoiceMuteButton.shown)
	env7.ChatFrameChannelButton = nil
	env7.CHAT_FRAMES = { "ChatFrame1", "ChatFrame3" }
	addon7.module.set("chat_layout", "enabled", true)
	check("a button or window this client does not have is skipped", not env7.ChatFrameMenuButton.shown and env7.ChatFrame1.time == 30)
end

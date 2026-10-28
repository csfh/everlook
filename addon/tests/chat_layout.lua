-- Chat layout: moves each chat window's edit box above its tab, or above the window when it has no tab, and hides the chat buttons, while those choices are on, and sets how long lines stay before they fade, including after the game rebuilds those windows.
return function(check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
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
	env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
	env.ChatFrame1, env.ChatFrame2 = chat_frame(120), chat_frame(60)
	env.ChatFrame1Tab = { name = "tab" }
	env.ChatFrameMenuButton, env.ChatFrameChannelButton = chat_button(true), chat_button(true)
	env.ChatFrameToggleVoiceMuteButton = chat_button(false)
	local function anchors(box)
		local list = {}
		for _, point in ipairs(box.points) do list[#list + 1] = table.concat({ point[1], type(point[2]) == "table" and point[2].name or point[2], point[3], point[4], point[5] }, ",") end
		return table.concat(list, ";")
	end
	check("chat layout changes nothing while off", anchors(env.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0" and env.ChatFrameMenuButton.shown)

	addon.module.set("chat_layout", "enabled", true)
	check("the edit box moves above the chat tab", anchors(env.ChatFrame1.editBox) == "BOTTOMLEFT,tab,TOPLEFT,-5,2;RIGHT,bar,RIGHT,8,0")
	check("a chat window with no tab uses the window itself",
		env.ChatFrame2.editBox.points[1][2] == env.ChatFrame2 and env.ChatFrame2.editBox.points[1][3] == "TOPLEFT")
	check("the chat buttons are hidden", not env.ChatFrameMenuButton.shown and not env.ChatFrameChannelButton.shown)
	check("the fade time starts at the game default", env.ChatFrame1.time == 120 and env.ChatFrame2.time == 120)
	addon.module.set("chat_layout", "fade_seconds", 30)
	check("the fade slider sets how long chat stays", env.ChatFrame1.time == 30 and env.ChatFrame2.time == 30)
	env.ChatFrameMenuButton:Show()
	check("a button the game shows again is hidden again", not env.ChatFrameMenuButton.shown)

	env.ChatFrame1.editBox.points = { { "TOPLEFT", "frame", "BOTTOMLEFT", -5, -2 } }
	event("UPDATE_CHAT_WINDOWS")
	check("a chat window refresh puts the edit box back on top", env.ChatFrame1.editBox.points[1][1] == "BOTTOMLEFT")

	addon.module.set("chat_layout", "editbox_top", false)
	check("clearing the edit box option restores its anchors", anchors(env.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0")
	addon.module.set("chat_layout", "hide_buttons", false)
	check("clearing the button option brings back the buttons that were shown", env.ChatFrameMenuButton.shown and env.ChatFrameChannelButton.shown and not env.ChatFrameToggleVoiceMuteButton.shown)
	addon.module.set("chat_layout", "editbox_top", true)
	addon.module.set("chat_layout", "hide_buttons", true)
	addon.module.set("chat_layout", "enabled", false)
	check("turning the module off restores anchors, fade time and buttons",
		anchors(env.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0"
		and env.ChatFrame1.time == 120 and env.ChatFrame2.time == 60
		and env.ChatFrameMenuButton.shown and env.ChatFrameChannelButton.shown and not env.ChatFrameToggleVoiceMuteButton.shown)
	env.ChatFrameChannelButton = nil
	env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame3" }
	addon.module.set("chat_layout", "enabled", true)
	check("a button or window this client does not have is skipped", not env.ChatFrameMenuButton.shown and env.ChatFrame1.time == 30)

	do
		-- Timestamps, through the chat filters of both the old globals and ChatFrameUtil.
		local addon, play, fire = lib.load_files({ "world", "module", "chat_layout" })
		play.GetGameTime = function()
			return 9, 5
		end
		local filters = {}
		play.ChatFrame_AddMessageEventFilter = function(event, callback)
			filters[event] = callback
		end
		play.ChatFrame_RemoveMessageEventFilter = function(event)
			filters[event] = nil
		end
		play.CHAT_FRAMES = {}
		addon.module.set("chat_layout", "enabled", true)
		addon.module.set("chat_layout", "timestamps", true)
		check("a plain chat line gains a timestamp", addon.chat_layout.stamp("Hello") == "09:05 Hello")
		-- Same rule as ChatFrameUtil.ProcessMessageEventFilters: a truthy first
		-- return drops the line, and a new message replaces the arguments that follow.
		local function shown_line(filter, message, author, extra)
			local discard, new_message, new_author, new_extra = filter(nil, "CHAT_MSG_SAY", message, author, extra)
			if discard then
				return nil
			end
			if new_message then
				return new_message, new_author, new_extra
			end
			return message, author, extra
		end
		local text, author, channel = shown_line(filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
		check("a timestamped line stays in chat with its sender", text == "09:05 Hello" and author == "Thrall" and channel == "1")
		play.issecretvalue = function(value)
			return value == "secret"
		end
		local secret_text, secret_author = shown_line(filters.CHAT_MSG_SAY, "secret", "Thrall")
		check("secret chat text stays in place", secret_text == "secret" and secret_author == "Thrall" and addon.chat_layout.stamp("secret") == "secret")
		play.issecretvalue = nil
		addon.module.set("chat_layout", "timestamps", false)
		check("turning timestamps off removes the prefix", addon.chat_layout.stamp("Hello") == "Hello" and filters.CHAT_MSG_SAY == nil)
		local util_filters = {}
		play.ChatFrameUtil = {
			AddMessageEventFilter = function(event, callback)
				util_filters[event] = callback
			end,
			RemoveMessageEventFilter = function(event)
				util_filters[event] = nil
			end,
		}
		addon.module.set("chat_layout", "timestamps", true)
		text, author = shown_line(util_filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
		check("timestamps register on ChatFrameUtil and keep the sender", text == "09:05 Hello" and author == "Thrall" and filters.CHAT_MSG_SAY == nil)
		addon.module.set("chat_layout", "timestamps", false)
		check("turning timestamps off removes the ChatFrameUtil filter", util_filters.CHAT_MSG_SAY == nil)
		play.ChatFrameUtil = nil
	end
end

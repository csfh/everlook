-- Hide clutter: stops a new talking head, center-screen zone name, red error, or raid warning when that choice is on, and hides the stance bar when that choice is on.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon5, env5, event5 = load_all()
	local function listening(names)
		local frame = { events = {} }
		for _, name in ipairs(names) do frame.events[name] = true end
		function frame:UnregisterEvent(name) self.events[name] = nil end
		function frame:RegisterEvent(name) self.events[name] = true end
		function frame:IsEventRegistered(name) return self.events[name] == true end
		return frame
	end
	env5.TalkingHeadFrame = listening({ "TALKINGHEAD_REQUESTED", "TALKINGHEAD_CLOSE" })
	env5.ZoneTextFrame = listening({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" })
	env5.UIErrorsFrame = listening({ "SYSMSG", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" })
	env5.RaidWarningFrame = listening({ "CHAT_MSG_RAID_WARNING" })
	local stance = { shown = true, hooks = {} }
	function stance:Hide() self.shown = false; self.insecure_hides = (self.insecure_hides or 0) + 1 end
	local function drive_stance()
		if stance.driver == "hide" then stance.shown = false; stance.statehidden = true end
		if stance.driver == "show" then stance.shown = true; stance.statehidden = nil end
	end
	env5.RegisterStateDriver = function(frame, state, value)
		check("stance uses the secure visibility driver", frame == stance and state == "visibility")
		frame.driver = value
		drive_stance()
	end
	env5.UnregisterStateDriver = function(frame, state)
		check("stance unregisters only its visibility driver", frame == stance and state == "visibility")
		frame.driver = nil
	end
	env5.securecallfunction = function(callback, frame) callback(frame) end
	function stance:Show()
		if self.shown then return end
		self.shown = true
		local hooks = self.hooks.OnShow
		if not hooks then return end
		for index = 1, #hooks do hooks[index](self) end
	end
	function stance:HookScript(name, callback)
		self.hooks[name] = self.hooks[name] or {}
		local list = self.hooks[name]
		list[#list + 1] = callback
	end
	function stance:Update()
		self.updates = (self.updates or 0) + 1
		self:Show()
	end
	env5.StanceBar = stance
	local function all_events_back()
		return env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env5.ZoneTextFrame.events.ZONE_CHANGED
			and env5.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA
			and env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING
	end
	check("clutter hiding changes nothing while the module is off", all_events_back())
	check("the stance bar stays up while its option is off", env5.StanceBar.shown and addon5.module.get("hide_clutter", "stance_bar") == false)
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("the stance option does nothing while the module is off", env5.StanceBar.shown and env5.StanceBar.updates == nil)
	addon5.module.set("hide_clutter", "stance_bar", false)
	addon5.module.set("hide_clutter", "error_messages", true)
	check("an option set while the module is off changes nothing", env5.UIErrorsFrame.events.UI_ERROR_MESSAGE)
	addon5.module.set("hide_clutter", "error_messages", false)

	addon5.module.set("hide_clutter", "enabled", true)
	check("the talking head stops listening for requests, and still closes",
		not env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env5.TalkingHeadFrame.events.TALKINGHEAD_CLOSE)
	check("zone text stops listening for zone changes",
		not env5.ZoneTextFrame.events.ZONE_CHANGED and not env5.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and not env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA)
	check("error messages and raid warnings stay on by default",
		env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)

	addon5.module.set("hide_clutter", "error_messages", true)
	check("hiding error messages leaves info messages and system messages",
		not env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.UIErrorsFrame.events.UI_INFO_MESSAGE and env5.UIErrorsFrame.events.SYSMSG)
	addon5.module.set("hide_clutter", "raid_warnings", true)
	check("hiding raid warnings stops the raid warning frame", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon5.module.set("hide_clutter", "zone_text", false)
	check("clearing one option brings that element back and leaves the others hidden",
		env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA and not env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon5.module.set("hide_clutter", "enabled", false)
	check("turning the module off restores every element", all_events_back())
	do
		-- Another addon had already stopped the raid warning frame listening. Hiding and then restoring must not
		-- start it again: only what Hide clutter itself stopped comes back.
		env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING = nil
		addon5.module.set("hide_clutter", "raid_warnings", true)
		addon5.module.set("hide_clutter", "enabled", true)
		addon5.module.set("hide_clutter", "enabled", false)
		check("an event another addon stopped is not started again", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
		env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING = true
	end
	env5.TalkingHeadFrame = nil
	addon5.module.set("hide_clutter", "enabled", true)
	check("a frame this client does not have is skipped and the rest still apply", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	check("enabling hide clutter leaves the stance bar up", env5.StanceBar.shown and env5.StanceBar.updates == nil)
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("the stance bar hides when its option is on", not env5.StanceBar.shown)
	check("stance hiding avoids protected Hide calls from addon code", stance.insecure_hides == nil and stance.driver == "hide")
	env5.StanceBar:Show()
	drive_stance()
	check("the secure driver hides the stance bar after the game shows it", not env5.StanceBar.shown)
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("clearing the option lets the bar decide and a show stays up", env5.StanceBar.updates == 1 and env5.StanceBar.shown)
	check("clearing the stance option removes the driver and secure hidden state", stance.driver == nil and stance.statehidden == nil)
	env5.InCombatLockdown = function() return true end
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("combat leaves the stance bar on screen", env5.StanceBar.shown)
	env5.StanceBar:Hide()
	env5.StanceBar:Show()
	check("a show during combat stays up", env5.StanceBar.shown)
	env5.InCombatLockdown = function() return false end
	event5("PLAYER_REGEN_ENABLED")
	check("leaving combat hides the stance bar", not env5.StanceBar.shown)
	env5.InCombatLockdown = function() return true end
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("disabling stance hiding waits to remove the driver during combat", stance.driver == "hide")
	env5.InCombatLockdown = function() return false end
	event5("PLAYER_REGEN_ENABLED")
	check("disabling stance hiding restores the bar after combat", stance.driver == nil and stance.shown)
	env5.RegisterStateDriver = nil
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("a missing secure driver leaves the stance bar alone", stance.driver == nil and stance.shown)
	env5.StanceBar = nil
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("a missing stance bar is skipped", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
end

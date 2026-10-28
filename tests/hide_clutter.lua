-- Hide clutter: stops a new talking head, center-screen zone name, red error, or raid warning when that choice is on, and hides the stance bar when that choice is on.
return function(check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local function listening(names)
		local frame = { events = {} }
		for _, name in ipairs(names) do frame.events[name] = true end
		function frame:UnregisterEvent(name) self.events[name] = nil end
		function frame:RegisterEvent(name) self.events[name] = true end
		function frame:IsEventRegistered(name) return self.events[name] == true end
		return frame
	end
	env.TalkingHeadFrame = listening({ "TALKINGHEAD_REQUESTED", "TALKINGHEAD_CLOSE" })
	env.ZoneTextFrame = listening({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" })
	env.UIErrorsFrame = listening({ "SYSMSG", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" })
	env.RaidWarningFrame = listening({ "CHAT_MSG_RAID_WARNING" })
	local stance = { shown = true, hooks = {} }
	function stance:Hide() self.shown = false; self.insecure_hides = (self.insecure_hides or 0) + 1 end
	local function drive_stance()
		if stance.driver == "hide" then stance.shown = false; stance.statehidden = true end
		if stance.driver == "show" then stance.shown = true; stance.statehidden = nil end
	end
	env.RegisterStateDriver = function(frame, state, value)
		check("stance uses the secure visibility driver", frame == stance and state == "visibility")
		frame.driver = value
		drive_stance()
	end
	env.UnregisterStateDriver = function(frame, state)
		check("stance unregisters only its visibility driver", frame == stance and state == "visibility")
		frame.driver = nil
	end
	env.securecallfunction = function(callback, frame) callback(frame) end
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
	env.StanceBar = stance
	local function all_events_back()
		return env.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env.ZoneTextFrame.events.ZONE_CHANGED
			and env.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and env.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA
			and env.UIErrorsFrame.events.UI_ERROR_MESSAGE and env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING
	end
	check("clutter hiding changes nothing while the module is off", all_events_back())
	check("the stance bar stays up while its option is off", env.StanceBar.shown and addon.module.get("hide_clutter", "stance_bar") == false)
	addon.module.set("hide_clutter", "stance_bar", true)
	check("the stance option does nothing while the module is off", env.StanceBar.shown and env.StanceBar.updates == nil)
	addon.module.set("hide_clutter", "stance_bar", false)
	addon.module.set("hide_clutter", "error_messages", true)
	check("an option set while the module is off changes nothing", env.UIErrorsFrame.events.UI_ERROR_MESSAGE)
	addon.module.set("hide_clutter", "error_messages", false)

	addon.module.set("hide_clutter", "enabled", true)
	check("the talking head stops listening for requests, and still closes",
		not env.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env.TalkingHeadFrame.events.TALKINGHEAD_CLOSE)
	check("zone text stops listening for zone changes",
		not env.ZoneTextFrame.events.ZONE_CHANGED and not env.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and not env.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA)
	check("error messages and raid warnings stay on by default",
		env.UIErrorsFrame.events.UI_ERROR_MESSAGE and env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)

	addon.module.set("hide_clutter", "error_messages", true)
	check("hiding error messages leaves info messages and system messages",
		not env.UIErrorsFrame.events.UI_ERROR_MESSAGE and env.UIErrorsFrame.events.UI_INFO_MESSAGE and env.UIErrorsFrame.events.SYSMSG)
	addon.module.set("hide_clutter", "raid_warnings", true)
	check("hiding raid warnings stops the raid warning frame", not env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon.module.set("hide_clutter", "zone_text", false)
	check("clearing one option brings that element back and leaves the others hidden",
		env.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA and not env.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and not env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon.module.set("hide_clutter", "enabled", false)
	check("turning the module off restores every element", all_events_back())
	do
		-- Another addon had already stopped the raid warning frame listening. Hiding and then restoring must not
		-- start it again: only what Hide clutter itself stopped comes back.
		env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING = nil
		addon.module.set("hide_clutter", "raid_warnings", true)
		addon.module.set("hide_clutter", "enabled", true)
		addon.module.set("hide_clutter", "enabled", false)
		check("an event another addon stopped is not started again", not env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
		env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING = true
	end
	env.TalkingHeadFrame = nil
	addon.module.set("hide_clutter", "enabled", true)
	check("a frame this client does not have is skipped and the rest still apply", not env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	check("enabling hide clutter leaves the stance bar up", env.StanceBar.shown and env.StanceBar.updates == nil)
	addon.module.set("hide_clutter", "stance_bar", true)
	check("the stance bar hides when its option is on", not env.StanceBar.shown)
	check("stance hiding avoids protected Hide calls from addon code", stance.insecure_hides == nil and stance.driver == "hide")
	env.StanceBar:Show()
	drive_stance()
	check("the secure driver hides the stance bar after the game shows it", not env.StanceBar.shown)
	addon.module.set("hide_clutter", "stance_bar", false)
	check("clearing the option lets the bar decide and a show stays up", env.StanceBar.updates == 1 and env.StanceBar.shown)
	check("clearing the stance option removes the driver and secure hidden state", stance.driver == nil and stance.statehidden == nil)
	env.InCombatLockdown = function() return true end
	addon.module.set("hide_clutter", "stance_bar", true)
	check("combat leaves the stance bar on screen", env.StanceBar.shown)
	env.StanceBar:Hide()
	env.StanceBar:Show()
	check("a show during combat stays up", env.StanceBar.shown)
	env.InCombatLockdown = function() return false end
	event("PLAYER_REGEN_ENABLED")
	check("leaving combat hides the stance bar", not env.StanceBar.shown)
	env.InCombatLockdown = function() return true end
	addon.module.set("hide_clutter", "stance_bar", false)
	check("disabling stance hiding waits to remove the driver during combat", stance.driver == "hide")
	env.InCombatLockdown = function() return false end
	event("PLAYER_REGEN_ENABLED")
	check("disabling stance hiding restores the bar after combat", stance.driver == nil and stance.shown)
	env.RegisterStateDriver = nil
	addon.module.set("hide_clutter", "stance_bar", true)
	check("a missing secure driver leaves the stance bar alone", stance.driver == nil and stance.shown)
	env.StanceBar = nil
	addon.module.set("hide_clutter", "stance_bar", false)
	check("a missing stance bar is skipped", not env.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
end

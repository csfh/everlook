-- Tracker text size: sets the quest tracker objectives to the size on Objective size, from 12 to 20, and keeps the headers two points larger.
return function(root, check, lib)
	local load_all = lib.load_all
	local tracker_addon, tracker_env, tracker_event = load_all()
	local text_setting = 4
	tracker_env.Enum = { EditModeObjectiveTrackerSetting = { TextSize = text_setting } }
	local tracker = { text_size = 12, line = 12, header = 14 }
	-- Blizzard's SetTextSize sets the two fonts and lays the tracker out again. Called from an
	-- addon that layout runs tainted, so only Blizzard's own code may call it.
	tracker.from_addon, tracker.in_blizzard = 0, false
	for size = 12, 22 do tracker_env["ObjectiveTrackerFont" .. size] = { size = size } end
	tracker_env.ObjectiveTrackerLineFont = {
		GetFont = function() return "tracker.ttf", tracker.line, "" end,
		SetFontObject = function(_, object) tracker.line = object.size end,
	}
	tracker_env.ObjectiveTrackerHeaderFont = { SetFontObject = function(_, object) tracker.header = object.size end }
	tracker_env.ObjectiveTrackerManager = { SetTextSize = function(_, size)
		if not tracker.in_blizzard then tracker.from_addon = tracker.from_addon + 1 end
		if size < 12 or size > 20 then return end
		tracker.line = size
		tracker.header = size + 2
	end }
	function tracker:IsInitialized() return self.initialized ~= false end
	function tracker:HasSetting(setting) return setting == text_setting end
	function tracker:UpdateSystem(value)
		self.initialized = true
		self.text_size = value
		self:UpdateSystemSettingTextSize()
	end
	function tracker:GetSettingValue(setting)
		if setting == text_setting then return self.text_size end
		return 0
	end
	function tracker:UpdateSystemSettingValue(setting, value)
		self.dirtied = true
		if setting ~= text_setting then return end
		self.text_size = value
		self:UpdateSystemSettingTextSize()
	end
	function tracker:UpdateSystemSettingTextSize()
		local size = self:GetSettingValue(text_setting)
		if size < 12 or size > 20 then return end
		tracker.in_blizzard = true
		tracker_env.ObjectiveTrackerManager:SetTextSize(size)
		tracker.in_blizzard = false
	end
	tracker_env.ObjectiveTrackerFrame = tracker
	check("the quest tracker keeps its text size while the module is off",
		tracker.line == 12 and tracker.header == 14 and tracker.text_size == 12 and tracker_addon.module.get("tracker_text_size", "text_size") == 16)
	tracker_addon.module.set("tracker_text_size", "text_size", 18)
	check("the tracker size does nothing while the module is off", tracker.line == 12 and tracker.header == 14)
	tracker_addon.module.set("tracker_text_size", "enabled", true)
	check("enabling the quest tracker enlarges text without changing Edit Mode", tracker.text_size == 12 and tracker.line == 18 and tracker.header == 20 and not tracker.dirtied)
	tracker_addon.module.set("tracker_text_size", "text_size", 30)
	check("quest tracker text size stays inside the tracker range", tracker_addon.module.get("tracker_text_size", "text_size") == 20 and tracker.line == 20 and tracker.header == 22)
	tracker_addon.module.set("tracker_text_size", "enabled", false)
	check("turning the quest tracker off restores the previous text size", tracker.text_size == 12 and tracker.line == 12 and tracker.header == 14)
	tracker.text_size = 13
	tracker:UpdateSystemSettingTextSize()
	check("edit mode owns the tracker size while the module is off", tracker.line == 13 and tracker.header == 15)
	tracker_env.ObjectiveTrackerFrame = nil
	tracker_addon.module.set("tracker_text_size", "enabled", true)
	check("a missing quest tracker is skipped", tracker.line == 13)
	tracker_env.ObjectiveTrackerFrame = tracker
	tracker.initialized = false
	tracker_addon.module.set("tracker_text_size", "enabled", true)
	check("an uninitialized quest tracker is left alone", tracker.line == 13)
	tracker:UpdateSystem(14)
	check("the quest tracker applies its size after late initialization", tracker.line == 20 and tracker.header == 22)
	tracker:UpdateSystem(15)
	check("a tracker layout refresh preserves the enabled objective size", tracker.line == 20)
	tracker_env.InCombatLockdown = function() return true end
	tracker_addon.module.set("tracker_text_size", "enabled", false)
	check("tracker restoration waits until combat ends", tracker.line == 20)
	tracker_env.InCombatLockdown = function() return false end
	tracker_event("PLAYER_REGEN_ENABLED")
	check("disabling the tracker restores the current layout size after combat", tracker.line == 15 and tracker.header == 17)
	tracker_addon.module.set("tracker_text_size", "enabled", true)
	tracker.in_blizzard = true
	tracker_env.ObjectiveTrackerManager:SetTextSize(17)
	tracker.in_blizzard = false
	tracker_addon.module.set("tracker_text_size", "enabled", false)
	check("disabling tracker sizing preserves a later external text size", tracker.line == 17 and tracker.header == 19 and tracker.text_size == 15 and not tracker.dirtied)
	tracker.line, tracker.header = 24, 26
	tracker_addon.module.set("tracker_text_size", "enabled", true)
	check("an external tracker size that cannot be restored is left alone", tracker.line == 24 and tracker.header == 26)
	tracker_addon.module.set("tracker_text_size", "enabled", false)
	check("the quest tracker size never goes through Blizzard's SetTextSize, whose layout would run tainted", tracker.from_addon == 0)
end

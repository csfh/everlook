-- Swing timers: sets the main hand, off hand, and ranged swing timers to the size on Timer scale, and leaves Edit Mode's saved size alone.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event = load_all()
	local scale_setting = 7
	env.Enum = env.Enum or {}
	env.Enum.EditModeSwingTimerSetting = { Scale = scale_setting }
	local function swing_bar(percent)
		local frame = {
			percent = percent, scale = percent / 100, initialized = true,
			systemInfo = { settings = { { setting = scale_setting, value = (percent - 50) / 10 } } },
			settingMap = { [scale_setting] = { value = (percent - 50) / 10, displayValue = percent } },
		}
		function frame:IsInitialized() return self.initialized end
		function frame:HasSetting(setting) return setting == scale_setting end
		function frame:UpdateSystem(value)
			self.initialized = true
			self.percent = value
			self.systemInfo.settings[1].value = (value - 50) / 10
			self.settingMap[scale_setting] = { value = (value - 50) / 10, displayValue = value }
			self:UpdateSystemSettingScale()
		end
		function frame:GetSettingValue(setting)
			if setting == scale_setting then return self.settingMap[setting].displayValue end
			return 0
		end
		function frame:UpdateSystemSettingValue(setting, value)
			self.dirtied = true
			if setting ~= scale_setting then return end
			self.percent = value
			self.systemInfo.settings[1].value = (value - 50) / 10
			self.settingMap[scale_setting] = { value = (value - 50) / 10, displayValue = value }
			self:UpdateSystemSettingScale()
		end
		function frame:UpdateSystemSettingScale()
			self:SetScale(self:GetSettingValue(scale_setting) / 100)
		end
		function frame:SetScale(value) self.scale = value end
		function frame:GetScale() return self.scale end
		return frame
	end
	env.SwingTimerMainHandFrame = swing_bar(100)
	env.SwingTimerOffHandFrame = swing_bar(80)
	env.SwingTimerRangedFrame = swing_bar(120)
	check("swing timers keep their edit mode scale while the module is off",
		env.SwingTimerMainHandFrame.scale == 1 and env.SwingTimerOffHandFrame.scale == 0.8 and env.SwingTimerRangedFrame.scale == 1.2
		and env.SwingTimerMainHandFrame.percent == 100 and addon.module.get("swing_timers", "scale") == 0.5)
	addon.module.set("swing_timers", "scale", 0.6)
	check("the scale does nothing while the module is off", env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", true)
	check("enabling swing timers changes the rendered scale without changing Edit Mode",
		env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 0.6
		and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerRangedFrame.scale == 0.6
		and not env.SwingTimerMainHandFrame.dirtied)
	check("swing scaling leaves the shared layout and display setting map untouched",
		env.SwingTimerMainHandFrame.systemInfo.settings[1].value == 5
		and env.SwingTimerMainHandFrame.settingMap[scale_setting].displayValue == 100
		and env.SwingTimerOffHandFrame.systemInfo.settings[1].value == 3)
	addon.module.set("swing_timers", "scale", 0.7)
	check("the scale slider updates the rendered scale", env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 0.7)
	env.SwingTimerMainHandFrame:UpdateSystemSettingScale()
	check("an edit mode refresh keeps the saved swing timer scale", env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 0.7)
	addon.module.set("swing_timers", "scale", 4)
	check("swing timer scale stays inside the slider", addon.module.get("swing_timers", "scale") == 1 and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerOffHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", false)
	check("turning swing timers off restores each edit mode scale",
		env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 1
		and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerOffHandFrame.scale == 0.8
		and env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 1.2)
	env.SwingTimerMainHandFrame:UpdateSystem(90)
	check("edit mode owns the scale while swing timers are off", env.SwingTimerMainHandFrame.scale == 0.9)
	env.SwingTimerOffHandFrame = nil
	addon.module.set("swing_timers", "enabled", true)
	check("a missing swing timer is skipped",
		env.SwingTimerMainHandFrame.percent == 90 and env.SwingTimerMainHandFrame.scale == 1
		and env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 1)
	env.SwingTimerMainHandFrame:UpdateSystem(150)
	check("a layout refresh reapplies the enabled swing scale", env.SwingTimerMainHandFrame.percent == 150 and env.SwingTimerMainHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", false)
	check("disabling swing scaling restores the new layout rather than the old one", env.SwingTimerMainHandFrame.percent == 150 and env.SwingTimerMainHandFrame.scale == 1.5)
	env.SwingTimerRangedFrame.initialized = false
	addon.module.set("swing_timers", "enabled", true)
	check("an uninitialized swing timer is left alone", env.SwingTimerRangedFrame.percent == 120)
	env.SwingTimerRangedFrame:UpdateSystem(90)
	check("a swing timer that initializes after the addon receives the enabled scale", env.SwingTimerRangedFrame.percent == 90 and env.SwingTimerRangedFrame.scale == 1)
	env.InCombatLockdown = function() return true end
	addon.module.set("swing_timers", "enabled", false)
	check("swing timer restoration waits until combat ends", env.SwingTimerRangedFrame.scale == 1)
	env.InCombatLockdown = function() return false end
	event("PLAYER_REGEN_ENABLED")
	check("swing timers restore after combat", env.SwingTimerRangedFrame.percent == 90 and env.SwingTimerRangedFrame.scale == 0.9)
	addon.module.set("swing_timers", "enabled", true)
	env.SwingTimerRangedFrame:SetScale(0.85)
	addon.module.set("swing_timers", "enabled", false)
	check("disabling swing scaling preserves a later external scale", env.SwingTimerRangedFrame.scale == 0.85)
	function env.SwingTimerRangedFrame:SetScale(value)
		self.scale = value == 0.7 and 0.69999998807907 or value
	end
	addon.module.set("swing_timers", "scale", 0.7)
	addon.module.set("swing_timers", "enabled", true)
	addon.module.set("swing_timers", "enabled", false)
	check("native scale rounding does not prevent restoration", env.SwingTimerRangedFrame.scale == 0.85)
end

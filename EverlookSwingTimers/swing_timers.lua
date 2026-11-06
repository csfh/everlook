local SwingTimers = Everlook:NewAddon("EverlookSwingTimers", {
	label = "Swing Timers",
	defaults = {
		change = false,
		scale = 0.5,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist. The timer frames themselves
-- come with Blizzard_SwingTimer, which may load later, so they aren't listed.
EverlookQA:Expect("EverlookSwingTimers", {
	"Enum.EditModeSwingTimerSetting.Scale",
	"hooksecurefunc",
	"InCombatLockdown",
})

-- The swing timers aren't in wow-ui-source 12.0.0; the Forever export names these frames
-- (Blizzard_SwingTimer.xml). UpdateSystemSettingScale applies Edit Mode's percent with SetScale.
-- This sets the visual scale only and never writes Edit Mode settings, which would taint them.
local NAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

local hooked = {}
local written = {} -- frames this session scaled, so turning this off only resets those
local applying = false
local waitingForCombat = false

local function scaleSetting()
	local settings = Enum and Enum.EditModeSwingTimerSetting
	return settings and settings.Scale
end

local function writable(frame, setting)
	return type(frame.IsInitialized) == "function" and frame:IsInitialized()
		and type(frame.HasSetting) == "function" and frame:HasSetting(setting)
		and type(frame.SetScale) == "function"
end

local function wantedScale()
	local scale = SwingTimers.db.scale
	if type(scale) ~= "number" then scale = SwingTimers.defaults.scale end
	return math.min(math.max(scale, 0.5), 1)
end

-- The scale the bar's Edit Mode layout names (its percent, 50 to 200, over 100), or our default.
local function layoutScale(frame, setting)
	if type(frame.GetSettingValue) == "function" then
		local ok, value = pcall(frame.GetSettingValue, frame, setting)
		if ok and type(value) == "number" and value >= 50 and value <= 200 then return value / 100 end
	end
	return SwingTimers.defaults.scale
end

function SwingTimers:UpdateFrame(frame)
	if applying then return end
	if InCombatLockdown() then
		waitingForCombat = true
		return
	end
	local setting = scaleSetting()
	if not setting or not writable(frame, setting) then return end
	local enabled = self.db.change
	if not enabled and not written[frame] then return end
	applying = true
	frame:SetScale(enabled and wantedScale() or layoutScale(frame, setting))
	applying = false
	written[frame] = enabled or nil
end

function SwingTimers:Apply()
	for _, name in ipairs(NAMES) do
		local frame = _G[name]
		if type(frame) == "table" then
			if not hooked[frame] and type(frame.UpdateSystem) == "function"
				and type(frame.UpdateSystemSettingScale) == "function" then
				local function refresh() self:UpdateFrame(frame) end
				hooksecurefunc(frame, "UpdateSystem", refresh)
				hooksecurefunc(frame, "UpdateSystemSettingScale", refresh)
				hooked[frame] = true
			end
			self:UpdateFrame(frame)
		end
	end
end

function SwingTimers:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Action Bars")
	page:Checkbox("change", "Change swing timer size",
		"Set the main hand, off hand and ranged swing timers to the size below. Edit Mode's saved size stays as it is. Changes wait until combat ends.")
	page:Slider("scale", "Timer scale", "From 50% to 100% of full size.", 0.5, 1, 0.1, EverlookPreferences.Percent)
end

function SwingTimers:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Apply")
	self:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_SwingTimer" then self:Apply() end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if waitingForCombat then
			waitingForCombat = false
			self:Apply()
		end
	end)
	self:Apply()
end

function SwingTimers:OnSettingChanged()
	self:Apply()
end

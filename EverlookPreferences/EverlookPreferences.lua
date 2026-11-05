-- The Everlook page in the game's Options window, /el and /everlook, the minimap button, and the
-- API every other Everlook addon uses to build its own page on Blizzard's Settings:
--
--   function MyAddon:OnInitialize()
--       local page = EverlookPreferences:NewPage(self, "Bags & Vendors")
--       page:Checkbox("enabled", "Enable", "What it does.")
--   end
local Preferences = Everlook:NewAddon("EverlookPreferences", {
	label = "Preferences",
	defaults = {
		showMinimap = true,
		minimapAngle = 160, -- degrees, 0 = right of the minimap, counter-clockwise
	},
})
EverlookPreferences = Preferences

-- The folders under Everlook, in this order. Each addon names its folder when it makes its page;
-- pages inside a folder sort alphabetically.
Preferences.FOLDERS = {
	{ name = "Quests", about = "Accepting and turning in quests, and skipping gossip." },
	{ name = "Bags & Vendors", about = "Repairs, junk, mail, containers, looting and gear upgrades." },
	{ name = "Action Bars", about = "Hotkey labels, spell ranks and swing timers." },
	{ name = "Chat & Social", about = "Chat labels, invites, summons, resurrections and duels." },
	{ name = "Tooltips", about = "Extra tooltip lines, and where the tooltip sits." },
	{ name = "World & Camera", about = "Camera, pointer, fonts, cinematics, flights, ground clutter and screen clutter." },
	{ name = "Developer", about = "Loading speed, the frame-time chart and the game-function check." },
}

-- Registered as this file loads, so they exist before any addon that depends on this one builds a page.
-- The register calls return the category and its layout (Blizzard_SettingsInbound.lua, 12.0.0).
Preferences.category, Preferences.layout = Settings.RegisterVerticalLayoutCategory("Everlook")
Settings.RegisterAddOnCategory(Preferences.category)

local folders = {} -- [name] = category
for _, folder in ipairs(Preferences.FOLDERS) do
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(Preferences.category, folder.name)
	if category.SetShouldSortAlphabetically then category:SetShouldSortAlphabetically(true) end
	if layout then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(folder.about)) end
	folders[folder.name] = category
end

-- The category a page goes under: its folder, or the Everlook page itself.
local function parentFor(folder)
	if folder == nil then return Preferences.category end
	return assert(folders[folder], "EverlookPreferences: no folder named " .. tostring(folder))
end

local Page = {}
Page.__index = Page

-- A page titled addon.label in one of the FOLDERS. Its controls read and write addon.db.
-- Call it from the addon's OnInitialize, which is when addon.db exists.
function Preferences:NewPage(addon, folder)
	assert(addon.db, "EverlookPreferences:NewPage needs addon.db; call it from OnInitialize")
	return setmetatable({
		addon = addon,
		category = Settings.RegisterVerticalLayoutSubcategory(parentFor(folder), addon.label),
	}, Page)
end

-- Registers addon.db[key] with Blizzard's Settings, defaulting to addon.defaults[key]. When the player
-- changes it, addon:OnSettingChanged(key, value) is called if the addon has one.
function Page:Register(key, label)
	local addon = self.addon
	local variable = addon.name .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(self.category, variable, key, addon.db,
		type(addon.defaults[key]), label, addon.defaults[key])
	-- The callback gets (owner, setting, value); Blizzard_Settings.lua, wow-ui-source 12.0.0.
	Settings.SetOnValueChangedCallback(variable, function(_, _, value)
		if addon.OnSettingChanged then addon:OnSettingChanged(key, value) end
	end)
	return setting
end

-- A page that shows `frame` as it is: for pages that draw their own content instead of a list of
-- settings. Titled `title`, or addon.label, in `folder`. The Options window parents and sizes the frame.
function Preferences:NewCanvasPage(addon, frame, title, folder)
	return Settings.RegisterCanvasLayoutSubcategory(parentFor(folder), frame, title or addon.label)
end

-- A checkbox bound to addon.db[key].
function Page:Checkbox(key, label, tooltip)
	local setting = self:Register(key, label)
	Settings.CreateCheckbox(self.category, setting, tooltip)
	return setting
end

-- A slider bound to addon.db[key], from min to max in steps of step. format(value) gives the
-- text beside it; Preferences.Percent shows 0.5 as "50%".
function Page:Slider(key, label, tooltip, min, max, step, format)
	local setting = self:Register(key, label)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format or tostring)
	Settings.CreateSlider(self.category, setting, options, tooltip)
	return setting
end

function Preferences.Percent(value)
	return math.floor(value * 100 + 0.5) .. "%"
end

-- Opens the Everlook page, or closes the Options window if it's open.
function Preferences:Toggle()
	if SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	else
		Settings.OpenToCategory(self.category:GetID())
	end
end

SLASH_EVERLOOK1 = "/everlook"
SLASH_EVERLOOK2 = "/el"
SlashCmdList.EVERLOOK = function()
	Preferences:Toggle()
end

-- The Everlook page itself: the version, the minimap button, and what's in each folder.
function Preferences:OnInitialize()
	local layout = self.layout
	local version = C_AddOns.GetAddOnMetadata("Everlook", "Version")
	if layout then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Everlook " .. (version or ""))) end

	local home = setmetatable({ addon = self, category = self.category }, Page)
	home:Checkbox("showMinimap", "Show the minimap button", "The Everlook button on the edge of the minimap. /el opens these settings either way.")

	if layout then
		for _, folder in ipairs(self.FOLDERS) do
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(folder.name .. ": " .. folder.about))
		end
	end

	self:CreateMinimapButton()
	self.button:SetShown(self.db.showMinimap)
end

function Preferences:OnSettingChanged(key, value)
	if key == "showMinimap" and self.button then self.button:SetShown(value) end
end

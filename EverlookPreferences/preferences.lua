-- The Everlook page in the game's Options window, /el and /everlook, the minimap button, and the
-- API every other Everlook addon uses to build its own page on Blizzard's Settings:
--
--   function MyAddon:OnInitialize()
--       local page = EverlookPreferences:NewPage(self, "Bags & Loot")
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
	{ name = "Bags & Loot", about = "Containers, looting and gear upgrades." },
	{ name = "Vendors & Mail", about = "Repairs, junk, auction prices and taking mail." },
	{ name = "Action Bars", about = "Hotkey labels, spell ranks and swing timers." },
	{ name = "Unit Frames", about = "Health colors, class portraits, bar text and name size on the game's unit frames." },
	{ name = "Chat & Social", about = "Chat labels, invites, summons, resurrections and duels." },
	{ name = "Tooltips", about = "Extra tooltip lines, and where the tooltip sits." },
	{ name = "Interface", about = "Fonts, the theme, UI scale, the pointer and screen clutter." },
	{ name = "Graphics", about = "Graphics quality, ground clutter and loot sparkles." },
	{ name = "World & Camera", about = "Camera distance, cinematics and flight times." },
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

-- Every page made, for the catalog on the Everlook page: { addon, folder, category }.
Preferences.pages = {}

local function remember(addon, folder, category)
	Preferences.pages[#Preferences.pages + 1] = { addon = addon, folder = folder, category = category }
	return category
end

-- A page titled addon.label in one of the FOLDERS. Its controls read and write addon.db.
-- Call it from the addon's OnInitialize, which is when addon.db exists.
function Preferences:NewPage(addon, folder)
	assert(addon.db, "EverlookPreferences:NewPage needs addon.db; call it from OnInitialize")
	local category = Settings.RegisterVerticalLayoutSubcategory(parentFor(folder), addon.label)
	return setmetatable({ addon = addon, category = remember(addon, folder, category) }, Page)
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
	return remember(addon, folder, Settings.RegisterCanvasLayoutSubcategory(parentFor(folder), frame, title or addon.label))
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

-- A dropdown bound to addon.db[key]. `choices` lists { value, label } in menu order, or is a
-- function returning that list; the Options window asks each time the menu opens
-- (Blizzard_Settings.lua, 12.0.0).
function Page:Dropdown(key, label, tooltip, choices)
	local setting = self:Register(key, label)
	Settings.CreateDropdown(self.category, setting, function()
		local container = Settings.CreateControlTextContainer()
		local list = type(choices) == "function" and choices() or choices
		for _, choice in ipairs(list) do container:Add(choice[1], choice[2]) end
		return container:GetData()
	end, tooltip)
	return setting
end

function Preferences.Percent(value)
	return math.floor(value * 100 + 0.5) .. "%"
end

-- Opens the Options window on the Everlook page. It doesn't close it: HideUIPanel from addon code
-- goes through the panel manager's attributes (UIParentPanelManager.lua, 12.0.0) and taints it, and
-- every window the game opens after that, Edit Mode included, runs tainted and trips over secret
-- values in the unit frames. Escape and the window's own close button close it.
-- Settings.OpenToCategory goes through C_SettingsUtil (Blizzard_Settings.lua, 12.0.0).
function Preferences:Open()
	Settings.OpenToCategory(self.category:GetID())
end

SLASH_EVERLOOK1 = "/everlook"
SLASH_EVERLOOK2 = "/el"
SlashCmdList.EVERLOOK = function()
	Preferences:Open()
end

-- The catalog: each folder in order, what it's for as its header's tooltip, and a row per page,
-- alphabetical, whose Open button goes to that page. The row's tooltip is the addon's Notes.
-- Search finds the pages by their own names, so the rows stay out of it, as Blizzard's buttons
-- that open a category do (CreateSettingsButtonInitializer, Blizzard_SettingControls.lua, 12.0.0).
function Preferences:BuildCatalog()
	local layout = self.layout
	if not layout then return end
	local byFolder = {}
	for _, page in ipairs(self.pages) do
		if page.folder then
			byFolder[page.folder] = byFolder[page.folder] or {}
			table.insert(byFolder[page.folder], page)
		end
	end
	for _, folder in ipairs(self.FOLDERS) do
		local pages = byFolder[folder.name]
		if pages then
			table.sort(pages, function(a, b) return a.addon.label < b.addon.label end)
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(folder.name, folder.about))
			for _, page in ipairs(pages) do
				local notes = C_AddOns.GetAddOnMetadata(page.addon.name, "Notes")
				layout:AddInitializer(CreateSettingsButtonInitializer(page.addon.label, "Open", function()
					Settings.OpenToCategory(page.category:GetID())
				end, notes, false))
			end
		end
	end
end

-- The Everlook page itself: the version, the minimap button, and the catalog.
function Preferences:OnInitialize()
	local layout = self.layout
	local version = C_AddOns.GetAddOnMetadata("Everlook", "Version")
	if layout then layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Everlook " .. (version or ""))) end

	local home = setmetatable({ addon = self, category = self.category }, Page)
	home:Checkbox("showMinimap", "Show the minimap button", "The Everlook button on the edge of the minimap. /el opens these settings either way.")

	-- Every Everlook addon has made its page by login: they make them as they load.
	self:RegisterEvent("PLAYER_LOGIN", function() self:BuildCatalog() end)

	self:CreateMinimapButton()
	self.button:SetShown(self.db.showMinimap)
end

function Preferences:OnSettingChanged(key, value)
	if key == "showMinimap" and self.button then self.button:SetShown(value) end
end

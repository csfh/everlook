local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookPreferences")

check(EverlookPreferences == Everlook:GetAddon("EverlookPreferences"), "EverlookPreferences is a global and an Everlook addon")
check(EverlookPreferences.category and EverlookPreferences.category.name == "Everlook",
	"the Everlook page exists before any other addon loads")

-- An addon building its page, the way the feature addons do.
local addon = Everlook:NewAddon("TestAddon", {
	label = "Test",
	defaults = { flag = true, other = false },
})
local settings = {}
local register = Settings.RegisterAddOnSetting
Settings.RegisterAddOnSetting = function(...)
	local setting = register(...)
	settings[setting.key] = setting
	return setting
end
function addon:OnInitialize()
	local page = EverlookPreferences:NewPage(self)
	page:Checkbox("flag", "Flag", "A flag.")
	page:Checkbox("other", "Other", "Another.")
end
t.reset()
t.fire("ADDON_LOADED", "TestAddon")
Settings.RegisterAddOnSetting = register

check(has("page Test"), "NewPage makes a sub-page titled with the addon's label")
check(has("checkbox flag") and has("checkbox other"), "Checkbox adds a checkbox per call, on the same page")
local flag = settings.flag
check(flag.tbl == addon.db and flag.varType == "boolean" and flag.default == true,
	"a checkbox reads and writes addon.db with the addon's default")
check(flag.variable == "TestAddon_flag", "setting names are unique per addon")

-- Sliders and change notifications.
local sliding = Everlook:NewAddon("Sliding", { label = "Sliding", defaults = { scale = 0.5, on = true } })
local changes = {}
function sliding:OnInitialize()
	local page = EverlookPreferences:NewPage(self)
	page:Slider("scale", "Scale", "How big.", 0.5, 1, 0.1, EverlookPreferences.Percent)
	page:Checkbox("on", "On", "Whether.")
end
function sliding:OnSettingChanged(key, value) changes[#changes + 1] = key .. "=" .. tostring(value) end
t.reset()
t.fire("ADDON_LOADED", "Sliding")
local slider = t.settings.Sliding_scale.slider
check(has("slider scale") and slider.min == 0.5 and slider.max == 1 and slider.step == 0.1, "Slider has its range and step")
check(slider.format(0.7) == "70%", "Percent shows the value as a percentage")
t.change("Sliding_scale", 0.8)
t.change("Sliding_on", false)
check(sliding.db.scale == 0.8 and changes[1] == "scale=0.8" and changes[2] == "on=false",
	"a change in the Options window reaches addon:OnSettingChanged")
t.change("TestAddon_flag", false)
check(true, "an addon without OnSettingChanged ignores changes")

-- Canvas pages: a frame the addon draws itself.
local registered
local registerCanvas = Settings.RegisterCanvasLayoutSubcategory
Settings.RegisterCanvasLayoutSubcategory = function(parent, frame, name)
	registered = { parent = parent, frame = frame, name = name }
	return { name = name }
end
local canvasFrame = t.widget("Canvas")
local canvas = EverlookPreferences:NewCanvasPage(sliding, canvasFrame)
check(registered.parent == EverlookPreferences.category and registered.frame == canvasFrame and registered.name == "Sliding"
	and canvas.name == "Sliding", "NewCanvasPage puts the addon's own frame under Everlook, titled with its label")
Settings.RegisterCanvasLayoutSubcategory = registerCanvas

-- Folders, in a fixed order, each sorting its pages.
local order = {}
for i, folder in ipairs(EverlookPreferences.FOLDERS) do order[i] = folder.name end
check(table.concat(order, ", ") == "Quests, Bags & Loot, Vendors & Mail, Action Bars, Unit Frames, Chat & Social, "
	.. "Tooltips, Interface, Graphics, World & Camera, Developer", "the eleven folders, in order, with Developer last")
local foldered = Everlook:NewAddon("Foldered", { label = "Foldered", defaults = { on = true } })
local foldered_page
function foldered:OnInitialize() foldered_page = EverlookPreferences:NewPage(self, "Tooltips") end
t.fire("ADDON_LOADED", "Foldered")
check(foldered_page.category.parent.name == "Tooltips" and foldered_page.category.parent.parent == EverlookPreferences.category,
	"a page goes in the folder it names, under Everlook")
check(foldered_page.category.parent.sorted == true, "and pages in a folder sort alphabetically")
check(t.headers["Tooltips"][1] ~= nil, "each folder's page says what's in it")
check(not pcall(EverlookPreferences.NewPage, EverlookPreferences, foldered, "Nowhere"), "an unknown folder is an error")

-- More pages for the catalog: two in Interface, made out of order, and a canvas page in Developer.
local zeta = Everlook:NewAddon("Zeta", { label = "Zeta", defaults = {} })
function zeta:OnInitialize() EverlookPreferences:NewPage(self, "Interface") end
local alpha = Everlook:NewAddon("Alpha", { label = "Alpha", defaults = {} })
function alpha:OnInitialize() EverlookPreferences:NewPage(self, "Interface") end
t.fire("ADDON_LOADED", "Zeta")
t.fire("ADDON_LOADED", "Alpha")
local chart = Everlook:NewAddon("Chart", { label = "Chart", defaults = {} })
local chartPage = EverlookPreferences:NewCanvasPage(chart, t.widget("ChartCanvas"), nil, "Developer")

-- The Everlook page itself.
local home = t.headers["Everlook"]
check(home[1] == "Everlook 0.1.0", "the Everlook page shows the version")
check(#home == 1, "before login the catalog isn't built: the pages aren't all made yet")
t.fire("PLAYER_LOGIN")
-- The catalog: a header per folder that has pages, in the folders' order, then its pages' rows.
local lines = {}
for _, row in ipairs(t.rows["Everlook"]) do
	if row.header then lines[#lines + 1] = "# " .. row.header elseif row.button then lines[#lines + 1] = row.button end
end
check(table.concat(lines, " | ") == "# Everlook 0.1.0 | # Tooltips | Foldered | # Interface | Alpha | Zeta | # Developer | Chart | QA",
	"the catalog lists each folder's pages, folders in order, pages alphabetical (" .. table.concat(lines, " | ") .. ")")
local rows = {}
for _, row in ipairs(t.rows["Everlook"]) do
	if row.button then rows[row.button] = row end
	if row.header == "Interface" then check(row.tooltip and row.tooltip:find("Fonts"), "a folder's header says what's in it") end
end
check(rows.Alpha.tooltip == "Notes of Alpha" and rows.Alpha.buttonText == "Open", "a row shows the addon's Notes and an Open button")
check(rows.Alpha.search == false, "rows stay out of search, which finds the pages themselves")
t.reset()
rows.Chart.click()
check(has("open " .. chartPage:GetID()) and chartPage:GetID() ~= 1, "Open goes to that addon's page, a canvas page too")
local listed = 0
for _ in pairs(rows) do listed = listed + 1 end
check(listed == 5, "pages outside a folder aren't in the catalog")
check(t.settings.EverlookPreferences_showMinimap ~= nil and EverlookPreferences.db.showMinimap == true,
	"and a Show the minimap button checkbox, on")
t.change("EverlookPreferences_showMinimap", false)
check(EverlookMinimapButton.shown == false, "unticking it hides the button")
t.change("EverlookPreferences_showMinimap", true)
check(EverlookMinimapButton.shown == true, "ticking it shows it again")

local early = Everlook:NewAddon("Early", {})
check(not pcall(EverlookPreferences.NewPage, EverlookPreferences, early), "NewPage before OnInitialize errors instead of failing quietly")

-- /el and /everlook.
SettingsPanel:Hide()
t.reset()
SlashCmdList.EVERLOOK()
check(SLASH_EVERLOOK1 == "/everlook" and SLASH_EVERLOOK2 == "/el" and has("open 1"), "/el and /everlook open the Everlook page")
SettingsPanel:Show()
t.reset()
SlashCmdList.EVERLOOK()
check(has("open 1") and not has("close SettingsPanel"), "and never close the Options window, which would taint the game's panels")

t.done()

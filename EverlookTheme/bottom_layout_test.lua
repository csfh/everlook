local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme bottom layout")
local t, check, Theme = f.t, f.check, f.Theme
local Layout = Theme.BottomLayout

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- The numbers ---------------------------------------------------------------------------------------
-- Forever's row: 11 micro buttons 32 wide overlapping by 5 (centres 27 apart), 40 tall; the
-- backpack, four bags, the reagent bag and the 33-wide keyring; a 17-tall status bar.
local centers = {}
for k = 0, 10 do centers[#centers + 1] = 16 + 27 * k end
local geometry = { microCenters = centers, microHeight = 40, bagWidths = { 45, 45, 45, 45, 45, 45, 33 }, statusHeight = 17 }
local plan = Layout.Plan(geometry)
local gap = Theme.GAP
check(plan and plan.button == 36 and near(plan.width, 2 * (12 * 36 + 11 * plan.padding * 0.8) + gap),
	"square 36-unit buttons, and the row as wide as two bars side by side, their padding scaled with the icons")
check(math.abs(plan.padding * 0.8 - gap) <= 0.5 and near(plan.barGap, plan.padding * 0.8),
	"bars 2 to 5 have about the gap between buttons on screen")
-- The bags at 80%, padding 5 in their own units: 4 on screen.
local main, bags = 12 * 36 + 11 * gap, (6 * 45 + 33) * 0.8 + 6 * 5 * 0.8
local firstTile = plan.microX + centers[1] * plan.scale - plan.tile / 2
local lastTile = plan.microX + centers[#centers] * plan.scale + plan.tile / 2
check(near(firstTile, -plan.half + main + plan.outerGap) and near(lastTile, plan.half - bags - plan.outerGap),
	"the micro tiles start and end the same gap from the main bar and the bags")
check(near(plan.microGap + plan.tile, centers[2] * plan.scale - centers[1] * plan.scale),
	"between the micro tiles the same micro gap")
check(math.abs(plan.microGap - gap) <= 1 and math.abs(plan.outerGap - gap) <= 1,
	"both within a unit of the gap everywhere else")
check(plan.row == gap + 17 + gap and plan.above == plan.row + 36 + gap and plan.top == plan.above + 36 + gap,
	"the main row sits a gap above the experience bar, bars 2 and 3 a gap above it, bars 4 and 5 above them")
check(near(plan.microY, plan.row + (36 - 40 * plan.scale) / 2), "the micro buttons are centred on the row")
local twelve = {}
for k = 0, 11 do twelve[#twelve + 1] = 16 + 27 * k end
local wider = Layout.Plan({ microCenters = twelve, microHeight = 40, bagWidths = geometry.bagWidths, statusHeight = 17 })
check(plan.padding <= 5 and plan.percent <= 100, "tight and slim, as chosen: no padding above the gap, no micro size above 100%")
check(wider and math.abs(wider.microGap - gap) <= 1.5 and math.abs(wider.outerGap - gap) <= 1.5,
	"a twelfth micro button can't fit at 70%, the smallest size, so the rows get more padding instead, gaps still even")
check(Layout.Plan({ microCenters = { 16 }, microHeight = 40, bagWidths = { 45 }, statusHeight = 17 }) == nil,
	"one micro button gives nothing to space out: no plan")

-- The game ------------------------------------------------------------------------------------------
Enum = Enum or {}
Enum.EditModeSystem = { ActionBar = 0, MicroMenu = 4, Bags = 5, StatusTrackingBar = 6, VehicleLeaveButton = 9, UnitFrame = 1,
	TotemActionBar = 10, ChatFrame = 11 }
Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 }
Enum.EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5, StanceBar = 11,
	PetActionBar = 12, PossessActionBar = 13 }
Enum.ActionBarOrientation = { Horizontal = 0, Vertical = 1 }
Enum.EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4 }
Enum.EditModeMicroMenuSetting = { Orientation = 0, Order = 1, Size = 2 }
Enum.EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 }
Enum.EditModeStatusTrackingBarSetting = { Size = 0 }
Enum.EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 }
Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 5 } }

local function system(kind, index, settings)
	local rows = {}
	for setting, value in pairs(settings or {}) do rows[#rows + 1] = { setting = setting, value = value } end
	return { system = kind, systemIndex = index, settings = rows, isInDefaultPosition = true,
		anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 } }
end
local S = Enum.EditModeSystem
-- The chat window, where the game's default layout has it (EditModePresetLayouts.lua).
function chatSystem()
	local item = system(S.ChatFrame, nil)
	item.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = 35, offsetY = 145 }
	return item
end
local B = Enum.EditModeActionBarSystemIndices
local function modern()
	return { layoutName = "Modern", layoutType = 0, systems = {
		system(S.ActionBar, B.MainBar, { [4] = 2 }), system(S.ActionBar, B.Bar2, { [4] = 2 }),
		system(S.ActionBar, B.Bar3, { [4] = 2 }), system(S.ActionBar, B.RightBar1, { [0] = 1 }),
		system(S.ActionBar, B.RightBar2, { [0] = 1 }), system(S.ActionBar, B.StanceBar),
		system(S.ActionBar, B.PetActionBar), system(S.ActionBar, B.PossessActionBar),
		system(S.VehicleLeaveButton, nil), system(S.TotemActionBar, nil),
		system(S.MicroMenu, nil, { [2] = 6 }), system(S.Bags, nil, { [2] = 5 }),
		system(S.StatusTrackingBar, 1, { [0] = 10 }), system(S.StatusTrackingBar, 2, { [0] = 10 }),
		system(S.UnitFrame, 1, { [7] = 3 }), chatSystem(),
	} }
end
EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function()
	return { modern(), { layoutName = "Classic", layoutType = 0, systems = {} } }
end }

local saved = { layouts = {}, activeLayout = 1 }
local calls = {}
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, inner in pairs(value) do result[key] = copy(inner) end
	return result
end
-- The game hands layouts back with offsets rounded to a tenth and an empty second anchor.
local function asGameReturns(info)
	local result = copy(info)
	for _, layout in ipairs(result.layouts) do
		for _, item in ipairs(layout.systems or {}) do
			local anchor = item.anchorInfo
			if anchor then
				anchor.offsetX = math.floor(anchor.offsetX * 10 + 0.5) / 10
				anchor.offsetY = math.floor(anchor.offsetY * 10 + 0.5) / 10
			end
			item.anchorInfo2 = {}
		end
	end
	return result
end
C_EditMode = {
	GetLayouts = function() return asGameReturns(saved) end,
	SaveLayouts = function(info)
		calls[#calls + 1] = "save"
		saved.layouts = copy(info.layouts)
	end,
	SetActiveLayout = function(index)
		calls[#calls + 1] = "active " .. index
		saved.activeLayout = index
	end,
	OnLayoutAdded = function(index, activate)
		calls[#calls + 1] = "added " .. index
		if activate then saved.activeLayout = index end
	end,
	GetEditModeDefaultLayout = function() return 1 end,
}
local editing = false
EditModeManagerFrame = { IsEditModeActive = function() return editing end }

-- The frames it measures.
function t.Widget:GetLeft() return self.left end
function t.Widget:GetCenter() return self.center end
function t.Widget:GetHeight() return self.height end
function t.Widget:GetWidth() return self.width end
MicroMenu = t.widget("MicroMenu")
MicroMenu.left, MicroMenu.height = 100, 40
local microButtons = {}
for k, x in ipairs(centers) do
	local button = t.widget()
	button.shown, button.layoutIndex, button.center = true, k, 100 + x
	microButtons[k] = button
end
function MicroMenu:GetChildren() return unpack(microButtons) end
BagsBar = t.widget("BagsBar")
local bagButtons = {}
for _, width in ipairs(geometry.bagWidths) do
	local button = t.widget()
	button.shown, button.width = true, width
	bagButtons[#bagButtons + 1] = button
end
MainMenuBarBagManager = { EnumerateBagButtons = function() return ipairs(bagButtons) end }
MainStatusTrackingBarContainer.height = 17

local function ours()
	for position, item in ipairs(saved.layouts) do
		if item.layoutName == "Everlook" then return item, position + 2 end
	end
end
local function find(layout, kind, index)
	for _, item in ipairs(layout.systems) do
		if item.system == kind and item.systemIndex == index then return item end
	end
end
local function setting(item, which)
	for _, row in ipairs(item.settings) do
		if row.setting == which then return row.value end
	end
end

-- On ------------------------------------------------------------------------------------------------
t.change("EverlookTheme_bottomLayout", true)
local layout, index = ours()
check(layout and layout.layoutType == 2 and index == 3 and calls[1] == "save" and calls[2] == "added 3",
	"on: a character layout named Everlook is saved and added as the active one")
local mainBar, bar2, bar3 = find(layout, S.ActionBar, B.MainBar), find(layout, S.ActionBar, B.Bar2), find(layout, S.ActionBar, B.Bar3)
check(setting(mainBar, 4) == 5 and setting(bar2, 4) == plan.padding and setting(bar3, 4) == plan.padding
	and setting(mainBar, 3) == 3 and setting(bar2, 3) == 3,
	"the main bar's padding is 5, 4 on screen at 80%, bars 2 and 3 the padding that fills the row")
local bar4, bar5 = find(layout, S.ActionBar, B.RightBar1), find(layout, S.ActionBar, B.RightBar2)
check(setting(bar4, 0) == 0 and setting(bar5, 0) == 0 and setting(bar4, 1) == 1 and setting(bar4, 3) == 3
	and bar4.anchorInfo.point == "BOTTOMLEFT" and near(bar4.anchorInfo.offsetY, plan.top)
	and bar5.anchorInfo.point == "BOTTOMRIGHT" and near(bar5.anchorInfo.offsetX, plan.half),
	"bars 4 and 5 are turned into rows of one, at the same size, on top")
check(not bar2.isInDefaultPosition and bar2.anchorInfo.point == "BOTTOMLEFT" and near(bar2.anchorInfo.offsetX, -plan.half)
	and near(bar2.anchorInfo.offsetY, plan.above) and bar3.anchorInfo.point == "BOTTOMRIGHT" and near(bar3.anchorInfo.offsetX, plan.half),
	"bars 2 and 3 sit on the row's left and right edges, a gap above it")
local stance, pet = find(layout, S.ActionBar, B.StanceBar), find(layout, S.ActionBar, B.PetActionBar)
local totems = find(layout, S.TotemActionBar, nil)
check(not stance.isInDefaultPosition and near(stance.anchorInfo.offsetY, plan.top + 36 + gap)
	and pet.anchorInfo.point == "BOTTOMRIGHT" and not totems.isInDefaultPosition,
	"the stance, pet and totem bars get a place above bars 2 and 3")
local micro, bagsBar = find(layout, S.MicroMenu, nil), find(layout, S.Bags, nil)
check(setting(micro, 2) == (plan.percent - 70) / 5 and near(micro.anchorInfo.offsetX, plan.microX)
	and setting(bagsBar, 3) == 5 and setting(bagsBar, 2) == 1 and bagsBar.anchorInfo.point == "BOTTOMRIGHT"
	and near(bagsBar.anchorInfo.offsetX, plan.half),
	"the micro menu takes the size the plan chose, the bags 80% with 4 on screen between them, at the row's right edge")
local status1, status2 = find(layout, S.StatusTrackingBar, 1), find(layout, S.StatusTrackingBar, 2)
check(near(status1.anchorInfo.offsetY, gap) and near(status2.anchorInfo.offsetY, gap) and not status2.isInDefaultPosition,
	"both status bars sit on the same spot along the bottom")
check(setting(find(layout, S.UnitFrame, 1), 7) == 3 and find(layout, S.UnitFrame, 1).isInDefaultPosition,
	"everything else is the layout it was copied from")
check(Theme.BottomRow() and Theme.BottomRow().width == plan.width, "the row is known to the tiles and the track")

-- The game's answer, rounded as it hands layouts back: no save, again and again.
calls = {}
t.fire("EDIT_MODE_LAYOUTS_UPDATED")
t.fire("EDIT_MODE_LAYOUTS_UPDATED")
check(#calls == 0, "the game's rounded answer is not taken for a change, so nothing loops")

-- The player picks another layout: left there.
saved.activeLayout = 1
t.fire("EDIT_MODE_LAYOUTS_UPDATED")
check(saved.activeLayout == 1 and #calls == 0 and Theme.BottomRow() == nil,
	"a layout the player picks after that stays, and the tiles stop following the row")

-- Off ----------------------------------------------------------------------------------------------
t.change("EverlookTheme_bottomLayout", false)
check(#calls == 0 and saved.activeLayout == 1, "off on another layout: nothing changes")
saved.activeLayout = 3
t.change("EverlookTheme_bottomLayout", false)
check(calls[#calls] == "active 1" and saved.activeLayout == 1, "off on Everlook's layout: back to the game's default")

-- With the switch off, a player who picks Everlook's layout by hand keeps it.
saved.activeLayout = 3
t.fire("EDIT_MODE_LAYOUTS_UPDATED")
check(saved.activeLayout == 3, "off: Everlook's layout picked by hand in Edit Mode stays")
saved.activeLayout = 1

-- Waiting ------------------------------------------------------------------------------------------
calls = {}
t.combat = true
t.change("EverlookTheme_bottomLayout", true)
check(#calls == 0, "in combat nothing is saved")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(calls[#calls] == "active 3" and saved.activeLayout == 3, "after combat the existing Everlook layout is made active")
t.change("EverlookTheme_bottomLayout", false)
calls = {}
editing = true
t.change("EverlookTheme_bottomLayout", true)
check(#calls == 0, "with Edit Mode open nothing is saved")
editing = false
EventRegistry:Trigger("EditMode.Exit")
check(saved.activeLayout == 3, "and it applies when Edit Mode closes")
t.change("EverlookTheme_bottomLayout", false)

-- Turned on and off again and again: it still switches each time, with no new saves.
calls = {}
for _ = 1, 4 do
	t.change("EverlookTheme_bottomLayout", true)
	t.change("EverlookTheme_bottomLayout", false)
end
t.change("EverlookTheme_bottomLayout", true)
local saves = 0
for _, call in ipairs(calls) do if call == "save" then saves = saves + 1 end end
check(saved.activeLayout == 3 and saves == 0, "toggled many times, it still switches to Everlook's layout and saves nothing new")
t.change("EverlookTheme_bottomLayout", false)

-- The chat ------------------------------------------------------------------------------------------
-- The chat frame's bottom 200 units up; its input line reaches 30 below it.
function t.Widget:GetBottom() return self.bottom end
ChatFrame1.bottom, ChatFrame1EditBox.bottom, ChatFrame1EditBox.shown = 200, 170, true
saved = { layouts = {}, activeLayout = 1 }
calls = {}
t.change("EverlookTheme_chatDown", true)
layout = ours()
local chat = layout and find(layout, S.ChatFrame, nil)
check(chat and not chat.isInDefaultPosition and chat.anchorInfo.point == "BOTTOMLEFT"
	and chat.anchorInfo.relativePoint == "BOTTOMLEFT" and chat.anchorInfo.offsetX == 35 and near(chat.anchorInfo.offsetY, gap + 30),
	"chat on its own: the chat goes down until its input line is a gap above the screen's edge, level with the experience bar")
check(find(layout, S.ActionBar, B.Bar2).isInDefaultPosition and setting(find(layout, S.ActionBar, B.MainBar), 4) == 2,
	"and with the bottom block off, the bars stay as the game's default layout has them")
check(Theme.BottomRow() == nil, "the tiles don't follow a row that isn't laid out")
t.change("EverlookTheme_bottomLayout", true)
layout = ours()
check(not find(layout, S.ActionBar, B.Bar2).isInDefaultPosition and not find(layout, S.ChatFrame, nil).isInDefaultPosition,
	"both on: the block and the chat in one layout")
t.change("EverlookTheme_chatDown", false)
layout = ours()
check(find(layout, S.ChatFrame, nil).isInDefaultPosition and find(layout, S.ChatFrame, nil).anchorInfo.offsetY == 145
	and not find(layout, S.ActionBar, B.Bar2).isInDefaultPosition and saved.activeLayout == 3,
	"chat off, block on: the chat goes back to the game's default spot, the block stays")
t.change("EverlookTheme_chatDown", true)
t.change("EverlookTheme_bottomLayout", false)
layout = ours()
check(find(layout, S.ActionBar, B.Bar2).isInDefaultPosition and setting(find(layout, S.ActionBar, B.Bar2), 4) == 2
	and not find(layout, S.ChatFrame, nil).isInDefaultPosition and saved.activeLayout == 3,
	"block off, chat on: the bars go back to the game's defaults, the chat stays down")
t.change("EverlookTheme_chatDown", false)
check(saved.activeLayout == 1, "both off: back to the game's default layout")

-- The player's own layout: a chat they moved and bars with their own padding. A switch that is off
-- leaves its part as they had it.
local function mine()
	local layout = modern()
	layout.layoutName, layout.layoutType = "Mine", 2
	local chatItem = find(layout, S.ChatFrame, nil)
	chatItem.anchorInfo.offsetX, chatItem.anchorInfo.offsetY, chatItem.isInDefaultPosition = 300, 400, false
	find(layout, S.ActionBar, B.Bar2).settings[1].value = 9
	return layout
end
Theme.db.layoutTurnedOff = {}
saved = { layouts = { mine() }, activeLayout = 3 }
t.change("EverlookTheme_bottomLayout", true)
layout = ours()
check(find(layout, S.ChatFrame, nil).anchorInfo.offsetY == 400 and find(layout, S.ChatFrame, nil).anchorInfo.offsetX == 300,
	"block on only: the chat stays where the player had it")
t.change("EverlookTheme_bottomLayout", false)
Theme.db.layoutTurnedOff = {}
saved = { layouts = { mine() }, activeLayout = 3 }
t.change("EverlookTheme_chatDown", true)
layout = ours()
check(setting(find(layout, S.ActionBar, B.Bar2), 4) == 9, "chat on only: the bars keep the player's own padding")
t.change("EverlookTheme_chatDown", false)
check(Theme.db.layoutTurnedOff.chatDown == true, "a part turned off waits, saved, to be put back at the next write")

-- A full list ----------------------------------------------------------------------------------------
saved = { layouts = {}, activeLayout = 1 }
for k = 1, 5 do saved.layouts[k] = { layoutName = "Mine " .. k, layoutType = 2, systems = {} } end
calls = {}
t.change("EverlookTheme_bottomLayout", true)
check(#calls == 0 and t.printed("no room"), "with no room for another character layout nothing is saved, and it says so")
t.change("EverlookTheme_bottomLayout", false)

t.done()

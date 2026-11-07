local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme action bars")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn, shownTexture = f.panelOn, f.shownTexture

function t.Widget:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end

-- The main bar (MainActionBar.xml, 12.0.0): its frame, the gryphons, and two buttons in
-- actionButtons. Slot 1 holds a spell, slot 2 is empty.
local bar = MainActionBar
local actions = { [1] = true }
HasAction = function(slot) return actions[slot] == true end
local function button(slot)
	local made = t.widget()
	made.shown, made.action = true, slot
	made.SlotArt, made.SlotBackground = shownTexture(), shownTexture()
	made.HighlightTexture, made.CheckedTexture = shownTexture(), shownTexture()
	local normal = shownTexture()
	function made:GetNormalTexture() return normal end
	made.normal = normal
	-- ActionBarActionButtonMixin:Update, which the game runs on slot and page changes.
	function made:Update() end
	return made
end
local first, second = button(1), button(2)
bar.actionButtons = { first, second }
-- A divider from the bar's pool: a NineSlice frame of pieces.
local piece = shownTexture()
local divider = t.widget()
function divider:GetRegions() return piece end
local active = { divider }
bar.HorizontalDividersPool = { EnumerateActive = function()
	local index = 0
	return function()
		index = index + 1
		return active[index]
	end
end }
function bar:UpdateDividers() end
-- An extra bar that keeps no list: its buttons are found by name.
local extra = button(13)
MultiBarBottomLeftButton1 = extra
MultiBarBottomLeft = t.widget("MultiBarBottomLeft")

local function same(color, expected)
	return color and color[1] == expected[1] and color[2] == expected[2] and color[3] == expected[3]
end

t.change("EverlookTheme_actionBars", true)
local tile, empty, named = panelOn(first), panelOn(second), panelOn(extra)
check(bar.BorderArt.alpha == 0 and bar.EndCaps.LeftEndCap.shown and bar.EndCaps.RightEndCap.shown,
	"on: the bar's frame is gone, the gryphons are Hide Clutter's and stay")
check(first.SlotArt.alpha == 0 and first.SlotBackground.alpha == 0 and first.normal.alpha == 0,
	"on: the slot art and the normal texture are gone")
check(first.HighlightTexture:IsShown() and first.HighlightTexture.alpha == 1 and first.CheckedTexture.alpha == 1,
	"the highlight and checked states stay the game's")
check(not piece:IsShown(), "the dividers between the buttons are gone")
check(tile and tile.points[1][2] == first and tile.points[1][4] == 0 and tile.fill and tile.fill.layer == "BACKGROUND" and tile.fill.sublevel == -8
	and tile.line.layer == "OVERLAY", "each button is a tile: the solid under the icon, the line over it")
check(tile.fill.colorTexture[4] == Theme:Opacity(), "at the background opacity")
check(named and extra.SlotArt.alpha == 0, "a bar without a list has its buttons found by name")
check(same(tile.line.vertex, Theme.ACCENT) and same(empty.line.vertex, Theme.ACCENT_IDLE),
	"gold under a slot with an action, gray under an empty one")

actions[2] = true
second:Update()
check(same(empty.line.vertex, Theme.ACCENT), "the line follows the game's update of the slot")
actions[2] = nil
t.combat = true
second:Update()
check(same(empty.line.vertex, Theme.ACCENT_IDLE), "and in combat too, as it colors only the tile")
t.combat = false

piece:Show()
bar:UpdateDividers()
check(not piece:IsShown(), "a divider the game lays out again is hidden again")

t.change("EverlookTheme_backgroundOpacity", 0.8)
check(tile.fill.colorTexture[4] == 0.8, "the opacity slider reaches the tiles")
t.change("EverlookTheme_backgroundOpacity", 0.5)

-- Off in combat: the tiles go at once, the secure buttons' art waits for the end of combat.
t.combat = true
t.change("EverlookTheme_actionBars", false)
check(not tile:IsShown() and first.SlotArt.alpha == 0 and bar.BorderArt.alpha == 0,
	"off in combat: the tiles are hidden, the game's art waits")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(bar.BorderArt.alpha == 1 and first.SlotArt.alpha == 1 and first.SlotBackground.alpha == 1
	and first.normal.alpha == 1 and piece:IsShown() and not named:IsShown(),
	"off: every texture is back and every tile hidden")

-- The game hides the slot background itself while the bar art shows; off leaves that choice.
t.change("EverlookTheme_actionBars", true)
first.SlotBackground:Hide()
t.change("EverlookTheme_actionBars", false)
check(not first.SlotBackground:IsShown() and first.SlotBackground.alpha == 1, "off keeps the game's own shown state of the slot art")
first.SlotBackground:Show()

-- On in combat: nothing is drawn until combat ends.
t.combat = true
t.change("EverlookTheme_actionBars", true)
check(not tile:IsShown() and first.SlotArt.alpha == 1, "on in combat: nothing changes yet")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(tile:IsShown() and first.SlotArt.alpha == 0, "and the tiles come after combat")
t.change("EverlookTheme_actionBars", false)

t.done()

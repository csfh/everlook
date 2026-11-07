local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme status bars")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn = f.panelOn

-- Experience and reputation bars ----------------------------------------------------------------
-- The container is the frame. The bar itself is the child status bar (StatusTrackingBarTemplate,
-- forever 1.60.1):  the fill, its dark background, and the rested prediction.
local container = MainStatusTrackingBarContainer
local barArt = container.BarFrameTexture
local status = t.widget()
status.Background = f.shownTexture()
local fill = f.shownTexture()
status.value = 50
function status:GetStatusBarTexture() return fill end
function status:GetValue() return self.value end
function status:GetMinMaxValues() return 0, 100 end
function status:GetWidth() return 200 end
function status:SetValue(value) self.value = value end
function status:SetStatusBarTexture() end
local rested = f.shownTexture()
function rested:GetWidth() return self.width end
rested:SetWidth(150)
rested:Show()
local bar = t.widget()
bar.StatusBar = status
bar.ExhaustionLevelFillBar = rested
-- Where the game picks the bar's atlas (ExpBarOverrides.lua, ReputationBarOverrides.lua, 12.0.0).
function bar:UpdateStatusBarTextures() end
bar.shown = true
-- A reputation bar, not showing yet.
local repStatus = t.widget()
repStatus.Background, repStatus.value = f.shownTexture(), 40
local repFill = f.shownTexture()
function repStatus:GetStatusBarTexture() return repFill end
function repStatus:GetValue() return self.value end
function repStatus:GetMinMaxValues() return 0, 100 end
function repStatus:GetWidth() return 200 end
function repStatus:SetValue(value) self.value = value end
local rep = t.widget()
rep.StatusBar = repStatus
function rep:UpdateBarTextures() end
-- Indexed as StatusTrackingBarInfo.BarsEnum: Reputation 1, Experience 4.
container.bars = { [1] = rep, [4] = bar }
local restState = 1
GetRestState = function() return restState end

local function same(color, r, g, b, a)
	return color and color[1] == r and color[2] == g and color[3] == b and (a == nil or color[4] == a)
end

t.change("EverlookTheme_statusBars", true)
local panel = panelOn(container)
check(not barArt:IsShown() and not status.Background:IsShown() and fill.alpha == 0 and rested.alpha == 0,
	"on: the frame, the trough, the textured fill and the rested art are gone")
check(panel and panel.allPoints == status and panel.fill and panel.progress and panel.progress.width == 100,
	"on: a flat panel on the status bar, filled to the current value")
check(same(panel.progress.colorTexture, 0.22, 0.42, 0.72, 1) and panel.rested.width == 150,
	"on: rested by GetRestState before the game says, the fill is rested blue and keeps its reach")
check(same(panel.rested.colorTexture, 0.45, 0.6, 0.85, 0.6), "the rested reach is a lighter blue")

bar:UpdateStatusBarTextures(false)
check(same(panel.progress.colorTexture, 0.42, 0.30, 0.62, 1), "not rested, as the game says: purple")
bar:UpdateStatusBarTextures(true)
check(same(panel.progress.colorTexture, 0.22, 0.42, 0.72, 1), "rested again: blue")
restState = 2
status:SetValue(50)
check(same(panel.progress.colorTexture, 0.22, 0.42, 0.72, 1), "the game's own answer wins over GetRestState")

-- The reputation bar takes its place.
bar.shown, rep.shown = false, true
C_Reputation = { GetWatchedFactionData = function() return { factionID = 72, reaction = 4 } end }
repStatus:SetValue(40)
check(same(panel.progress.colorTexture, 0.9, 0.7, 0, 1),
	"reputation before the game says: the watched faction's reaction, neutral yellow")
rep:UpdateBarTextures(2, false)
check(same(panel.progress.colorTexture, 0.8, 0.3, 0.22, 1) and panel.progress.width == 80,
	"reputation: hostile is red, filled to its own value")
rep:UpdateBarTextures(6, true)
check(same(panel.progress.colorTexture, 0.22, 0.42, 0.72, 1), "paragon and renown are blue")
FACTION_BAR_COLORS = { [5] = { r = 0.1, g = 0.7, b = 0.2 } }
rep:UpdateBarTextures(5, false)
check(same(panel.progress.colorTexture, 0.1, 0.7, 0.2, 1), "the game's FACTION_BAR_COLORS wins when it has one")
FACTION_BAR_COLORS = nil
bar.shown, rep.shown = true, false
status:SetValue(50)

status:SetValue(25)
check(panel.progress.width == 50, "the fill follows the bar")
-- Forever puts the frame's alpha back itself; hidden, it stays out of sight.
barArt:SetAlpha(1)
check(not barArt:IsShown(), "the frame stays hidden when the game sets its alpha back")
barArt:Show()
status:SetValue(30)
check(not barArt:IsShown(), "and is hidden again if the game shows it")
-- Left at full alpha under the track, the trough would hide the background opacity.
status.Background:SetAlpha(1)
check(not status.Background:IsShown(), "the trough stays hidden when its alpha comes back")
local swapped = f.shownTexture()
function status:GetStatusBarTexture() return swapped end
status:SetStatusBarTexture("UI-HUD-ExperienceBar-Fill-Experience")
check(swapped.alpha == 0, "a fill texture the game sets later stays hidden")

rested:Hide()
status:SetValue(25)
check(not panel.rested:IsShown(), "no rested art, no rested fill")

-- With the bottom layout in use, the track spans the row and the fill is measured on it.
local row = Theme.BottomRow
Theme.BottomRow = function() return { width = 1150 } end
t.change("EverlookTheme_statusBars", false)
t.change("EverlookTheme_statusBars", true)
status:SetValue(50)
check(panel.width == 1150 and panel.points[#panel.points][1] == "BOTTOM" and panel.progress.width == 575,
	"with the bottom layout: the track is the row's width, centred on the bar, and filled across it")
Theme.BottomRow = row
t.change("EverlookTheme_statusBars", false)
t.change("EverlookTheme_statusBars", true)
check(panel.allPoints == status and panel.progress.width == 100, "without it: back on the bar")

t.change("EverlookTheme_statusBars", false)
check(barArt:IsShown() and status.Background:IsShown() and fill.alpha == 1 and rested.alpha == 1
	and not panel:IsShown(), "off: the game's bar is back and the flat panel is gone")

t.done()

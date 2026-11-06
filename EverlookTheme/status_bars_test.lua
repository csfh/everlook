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
container.bars = { bar }

t.change("EverlookTheme_statusBars", true)
local panel = panelOn(container)
check(barArt.alpha == 0 and status.Background.alpha == 0 and fill.alpha == 0 and rested.alpha == 0,
	"on: the frame, the trough, the textured fill and the rested art are gone")
check(panel and panel.allPoints == status and panel.fill and panel.progress and panel.progress.width == 100,
	"on: a flat panel on the status bar, filled to the current value")
local color = panel.progress.colorTexture
check(color and color[1] == 0.25 and color[2] == 0.78 and color[3] == 0.92 and panel.rested.width == 150,
	"on: the fill is the class color, and rested XP keeps its reach")

status:SetValue(25)
check(panel.progress.width == 50, "the fill follows the bar")
local swapped = f.shownTexture()
function status:GetStatusBarTexture() return swapped end
status:SetStatusBarTexture("UI-HUD-ExperienceBar-Fill-Experience")
check(swapped.alpha == 0, "a fill texture the game sets later stays hidden")

rested:Hide()
status:SetValue(25)
check(not panel.rested:IsShown(), "no rested art, no rested fill")

t.change("EverlookTheme_statusBars", false)
check(barArt.alpha == 1 and status.Background.alpha == 1 and fill.alpha == 1 and rested.alpha == 1
	and not panel:IsShown(), "off: the game's bar is back and the flat panel is gone")

t.done()
